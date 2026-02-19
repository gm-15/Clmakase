package com.oliveyoung.sale.service;

import com.oliveyoung.sale.dto.QueueEntryMessage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ZSetOperations;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.Set;
import java.util.UUID;

/**
 * 대기열 서비스 - Version C (Kafka 3-Broker 클러스터 + DLQ)
 *
 * [Version A와의 차이]
 * - KafkaClusterProducerService 주입 (Circuit Breaker 없음)
 * - Kafka 클러스터가 고가용성을 보장하므로 Redis 폴백 불필요
 * - Redis 로직 (대기열 관리)은 Version A와 동일
 *
 * [면접 포인트]
 * Q: "Version A와 C의 Redis 로직이 동일한데 왜 분리했나요?"
 * A: Kafka Producer 의존성이 다릅니다.
 *    Version A는 CircuitBreaker가 포함된 KafkaProducerService,
 *    Version C는 순수 KafkaClusterProducerService를 사용합니다.
 *    같은 인터페이스(QueueOperations)를 구현하므로
 *    Spring Profile로 런타임에 전환됩니다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("version-c")
public class QueueServiceVersionC implements QueueOperations {

    private static final String QUEUE_KEY = "purchase:queue";
    private static final String PROCESSING_KEY = "purchase:processing";
    private static final int MAX_QUEUE_SIZE = 10000;
    private static final int BATCH_SIZE = 10;

    private final RedisTemplate<String, Object> redisTemplate;
    private final KafkaClusterProducerService kafkaProducerService;

    @Override
    public QueueEntry enterQueue(String sessionId, Long productId) {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();

        Long queueSize = zSetOps.size(QUEUE_KEY);
        if (queueSize != null && queueSize >= MAX_QUEUE_SIZE) {
            throw new IllegalStateException("대기열이 가득 찼습니다. 잠시 후 다시 시도해주세요.");
        }

        String token = UUID.randomUUID().toString();
        long timestamp = System.currentTimeMillis();

        // Kafka 클러스터에 비동기 전송 (Circuit Breaker 없이 직접 전송)
        QueueEntryMessage message = new QueueEntryMessage(sessionId, productId, token, timestamp);
        kafkaProducerService.sendQueueEntry(message);

        int estimatedPosition = (queueSize != null) ? queueSize.intValue() + 1 : 1;

        log.info("대기열 진입 요청 (Version C) - sessionId: {}, estimatedPosition: {}", sessionId, estimatedPosition);

        return new QueueEntry(token, estimatedPosition, estimateWaitTime(estimatedPosition));
    }

    @Override
    public QueueStatus getQueueStatus(String sessionId, String token, Long productId) {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();
        String queueValue = sessionId + ":" + productId + ":" + token;

        Boolean isProcessing = redisTemplate.opsForSet().isMember(PROCESSING_KEY, queueValue);
        if (Boolean.TRUE.equals(isProcessing)) {
            return new QueueStatus(0, 0, true, false);
        }

        Long rank = zSetOps.rank(QUEUE_KEY, queueValue);
        if (rank == null) {
            return new QueueStatus(0, 0, false, true);
        }

        int position = rank.intValue() + 1;
        return new QueueStatus(position, estimateWaitTime(position), false, false);
    }

    @Scheduled(fixedRate = 1000)
    public void processQueue() {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();

        Set<Object> nextUsers = zSetOps.range(QUEUE_KEY, 0, BATCH_SIZE - 1);
        if (nextUsers == null || nextUsers.isEmpty()) {
            return;
        }

        for (Object user : nextUsers) {
            zSetOps.remove(QUEUE_KEY, user);
            redisTemplate.opsForSet().add(PROCESSING_KEY, user);
        }

        log.debug("대기열 처리 (Version C): {}명 이동", nextUsers.size());
    }

    @Override
    public void completeProcessing(String sessionId, String token, Long productId) {
        String queueValue = sessionId + ":" + productId + ":" + token;
        redisTemplate.opsForSet().remove(PROCESSING_KEY, queueValue);
        log.info("구매 완료 처리 (Version C) - sessionId: {}", sessionId);
    }

    private int estimateWaitTime(int position) {
        return (int) Math.ceil(position / 10.0);
    }
}
