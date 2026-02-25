package com.oliveyoung.sale.service;

import com.oliveyoung.sale.dto.QueueEntryMessage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ZSetOperations;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.util.Set;
import java.util.UUID;

/**
 * 대기열 서비스 - Version A (Circuit Breaker + 단일 Kafka 브로커)
 *
 * [면접 포인트]
 * Q: "왜 대기열을 Redis Sorted Set으로 구현했나요?"
 * A: 1) 시간순 정렬: score를 timestamp로 사용해 FIFO 보장
 *    2) O(log N) 순위 조회: ZRANK로 내 앞에 몇 명인지 즉시 확인
 *    3) 원자적 연산: ZADD, ZREM이 atomic하여 동시성 안전
 *    4) 범위 조회: ZRANGE로 상위 N명 일괄 처리 가능
 *
 *    List를 쓰면 순위 조회가 O(N)이고, DB Queue는 부하가 큽니다.
 *
 * Q: "대기열이 너무 길어지면?"
 * A: 1) 대기열 최대 길이 제한 (예: 10,000명)
 *    2) 초과 시 "잠시 후 다시 시도" 응답
 *    3) TTL 설정으로 오래된 대기자 자동 만료
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("!version-c & !local")
public class QueueService implements QueueOperations {

    private static final String QUEUE_KEY = "purchase:queue";
    private static final String PROCESSING_KEY = "purchase:processing";
    private static final int MAX_QUEUE_SIZE = 10000;
    private static final int BATCH_SIZE = 10; // 한 번에 처리할 수

    private final RedisTemplate<String, Object> redisTemplate;
    private final KafkaProducerService kafkaProducerService;

    /**
     * 대기열 진입 (Kafka를 통한 비동기 처리)
     *
     * [변경 전] 사용자 → Redis ZADD (직접)
     * [변경 후] 사용자 → Kafka Produce → Consumer → Redis ZADD
     *
     * Kafka가 버퍼 역할을 하여 트래픽 폭증 시 시스템을 보호합니다.
     * 토큰은 즉시 발급하고, 실제 Redis 등록은 Consumer가 비동기로 처리합니다.
     *
     * @param sessionId 사용자 세션 ID
     * @return 대기열 토큰 (대기열 이탈 및 상태 조회용)
     */
    public QueueEntry enterQueue(String sessionId, Long productId) {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();

        // 현재 대기열 크기 확인
        Long queueSize = zSetOps.size(QUEUE_KEY);
        if (queueSize != null && queueSize >= MAX_QUEUE_SIZE) {
            throw new IllegalStateException("대기열이 가득 찼습니다. 잠시 후 다시 시도해주세요.");
        }

        // 대기열 토큰 생성
        String token = UUID.randomUUID().toString();
        long timestamp = System.currentTimeMillis();

        // Kafka에 대기열 진입 메시지 발행 (비동기)
        QueueEntryMessage message = new QueueEntryMessage(sessionId, productId, token, timestamp);
        kafkaProducerService.sendQueueEntry(message);

        // 현재 대기열 크기 기반 예상 순위 (정확한 순위는 Consumer 처리 후 조회)
        int estimatedPosition = (queueSize != null) ? queueSize.intValue() + 1 : 1;

        log.info("대기열 진입 요청 (Kafka) - sessionId: {}, estimatedPosition: {}", sessionId, estimatedPosition);

        return new QueueEntry(token, estimatedPosition, estimateWaitTime(estimatedPosition));
    }

    /**
     * 대기 순번 조회
     *
     * [면접 포인트]
     * Q: "실시간 순번 업데이트를 어떻게 처리했나요?"
     * A: 클라이언트에서 2초 간격 Polling으로 구현했습니다.
     *
     *    WebSocket/SSE 대비 트레이드오프:
     *    - Polling: 구현 간단, 연결 관리 불필요, 서버 부하 예측 가능
     *    - WebSocket: 실시간성 좋지만 연결 유지 비용, EKS Pod 재시작 시 재연결 필요
     *
     *    시연용으로는 Polling이 충분하고,
     *    프로덕션에서는 SSE + Redis Pub/Sub 조합을 고려할 수 있습니다.
     */
    public QueueStatus getQueueStatus(String sessionId, String token, Long productId) {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();
        String queueValue = sessionId + ":" + productId + ":" + token;

        // 처리 중인지 확인
        Boolean isProcessing = redisTemplate.opsForSet().isMember(PROCESSING_KEY, queueValue);
        if (Boolean.TRUE.equals(isProcessing)) {
            return new QueueStatus(0, 0, true, false);
        }

        // 대기열에서 순위 조회
        Long rank = zSetOps.rank(QUEUE_KEY, queueValue);
        if (rank == null) {
            // 대기열에 없음 (이미 처리됨 또는 만료)
            return new QueueStatus(0, 0, false, true);
        }

        int position = rank.intValue() + 1;
        return new QueueStatus(position, estimateWaitTime(position), false, false);
    }

    /**
     * 대기열에서 다음 사용자들을 처리 상태로 이동
     * (스케줄러에서 주기적으로 호출)
     *
     * [면접 포인트]
     * Q: "대기열 처리 속도는 어떻게 조절하나요?"
     * A: 스케줄러가 1초마다 BATCH_SIZE(10명)씩 처리 상태로 이동합니다.
     *    이 값을 조절해 DB 부하와 처리 속도의 균형을 맞춥니다.
     *
     *    실제로는 DB 응답 시간, 에러율을 모니터링하며
     *    동적으로 조절하는 Adaptive Rate Limiting도 고려할 수 있습니다.
     */
    @Scheduled(fixedRate = 3000) // 3초마다 실행
    public void processQueue() {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();

        // 상위 N명 조회
        Set<Object> nextUsers = zSetOps.range(QUEUE_KEY, 0, BATCH_SIZE - 1);
        if (nextUsers == null || nextUsers.isEmpty()) {
            return;
        }

        for (Object user : nextUsers) {
            // 대기열에서 제거
            zSetOps.remove(QUEUE_KEY, user);
            // 처리 중 목록에 추가 (5분 후 자동 만료 - TTL은 별도 설정 필요)
            redisTemplate.opsForSet().add(PROCESSING_KEY, user);
        }

        log.debug("대기열 처리: {}명 이동", nextUsers.size());
    }

    /**
     * 구매 완료 후 처리 목록에서 제거
     */
    public void completeProcessing(String sessionId, String token, Long productId) {
        String queueValue = sessionId + ":" + productId + ":" + token;
        redisTemplate.opsForSet().remove(PROCESSING_KEY, queueValue);
        log.info("구매 완료 처리 - sessionId: {}", sessionId);
    }

    /**
     * 예상 대기 시간 계산 (초)
     */
    private int estimateWaitTime(int position) {
        // 3초마다 10명 처리 → 1명당 약 0.3초, position 기준 3초 단위 반올림
        return (int) Math.ceil(position / 10.0) * 3;
    }

}
