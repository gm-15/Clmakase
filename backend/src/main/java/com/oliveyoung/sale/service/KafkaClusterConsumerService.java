package com.oliveyoung.sale.service;

import com.oliveyoung.sale.config.KafkaClusterConfig;
import com.oliveyoung.sale.dto.QueueEntryMessage;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.kafka.annotation.DltHandler;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.annotation.RetryableTopic;
import org.springframework.kafka.retrytopic.DltStrategy;
import org.springframework.kafka.retrytopic.TopicSuffixingStrategy;
import org.springframework.retry.annotation.Backoff;
import org.springframework.stereotype.Service;

/**
 * Kafka Consumer 서비스 - Version C (Non-blocking Retry + DLT)
 *
 * [Blocking vs Non-blocking Retry]
 *
 * Blocking (Version A / 기존 DefaultErrorHandler 방식):
 *   메시지 실패 → 같은 파티션에서 재시도 → 뒤의 메시지 전부 대기 (Blocking!)
 *   ❌ 1개 메시지 장애가 전체 파티션을 멈춤
 *
 * Non-blocking (@RetryableTopic 방식):
 *   메시지 실패 → 별도 retry 토픽으로 발행 → 원본 파티션은 계속 처리
 *   ✅ 실패 메시지만 별도 트랙에서 재시도, 나머지는 정상 처리
 *
 *   [메시지 흐름]
 *   queue-entry-requests (실패)
 *     → queue-entry-requests-retry-0   (1초 후 재시도)
 *     → queue-entry-requests-retry-1   (5초 후 재시도)
 *     → queue-entry-requests-retry-2   (30초 후 재시도)
 *     → queue-entry-requests.DLT       (최종 실패 → 운영자 확인)
 *
 * [DLQ vs DLT]
 * - DLQ (Dead Letter Queue): RabbitMQ, SQS 등 Queue 기반 → 메시지를 '이동(Move)'
 * - DLT (Dead Letter Topic): Kafka Topic 기반 → 메시지를 '복사 발행(Publish)'
 *   Kafka는 한 번 기록된 로그를 삭제하지 않으므로, 원본 데이터 보존 + Replay 가능
 *
 * [면접 포인트]
 * Q: "DLQ 대신 DLT를 쓴 이유?"
 * A: Kafka는 Queue가 아닌 Topic(로그) 기반입니다.
 *    SQS DLQ는 실패 메시지를 이동(Move)하지만, Kafka DLT는 복사 발행(Publish)합니다.
 *    원본 토픽의 데이터가 보존되므로 offset 조정만으로 Replay가 가능하고,
 *    @RetryableTopic으로 Non-blocking Retry를 구현하여
 *    개별 메시지 실패가 전체 파티션을 막지 않습니다.
 *
 * Q: "Blocking Retry와 Non-blocking Retry 차이?"
 * A: Blocking은 같은 파티션 내에서 재시도하므로 뒤 메시지가 밀립니다.
 *    Non-blocking은 실패 메시지를 retry 토픽으로 보내고, 원본 파티션은 계속 진행합니다.
 *    대기열 시스템에서는 1개 실패가 전체 대기열을 멈추면 안 되므로
 *    Non-blocking 방식이 필수입니다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("version-c")
public class KafkaClusterConsumerService {

    private static final String QUEUE_KEY = "purchase:queue";
    private final RedisTemplate<String, Object> redisTemplate;
    private final MeterRegistry meterRegistry;
    private Counter dltCounter;
    private Counter retryCounter;

    @PostConstruct
    public void init() {
        dltCounter = Counter.builder("dlt_messages_total")
                .description("Total number of messages sent to DLT")
                .tag("topic", KafkaClusterConfig.DLT_TOPIC)
                .register(meterRegistry);

        retryCounter = Counter.builder("kafka_retry_total")
                .description("Total number of message retries")
                .tag("topic", KafkaClusterConfig.QUEUE_TOPIC)
                .register(meterRegistry);
    }

    /**
     * Non-blocking Retry Consumer
     *
     * @RetryableTopic이 자동으로 retry 토픽들을 생성하고 관리합니다.
     * - attempts = 4 → 최초 1회 + 재시도 3회
     * - backoff: 1초 → 5초 → 30초 (multiplier=5, 점진적 증가)
     * - SUFFIX_WITH_INDEX: retry-0, retry-1, retry-2 형태로 토픽 생성
     * - ALWAYS_RETRY_ON_ERROR: 모든 예외에 대해 재시도
     */
    @RetryableTopic(
            attempts = "4",
            backoff = @Backoff(delay = 1000, multiplier = 5, maxDelay = 30000),
            topicSuffixingStrategy = TopicSuffixingStrategy.SUFFIX_WITH_INDEX_VALUE,
            dltStrategy = DltStrategy.ALWAYS_RETRY_ON_ERROR,
            include = Exception.class
    )
    @KafkaListener(
            topics = KafkaClusterConfig.QUEUE_TOPIC,
            groupId = KafkaClusterConfig.CONSUMER_GROUP
    )
    public void consumeQueueEntry(QueueEntryMessage message) {
        String queueValue = message.getSessionId() + ":" + message.getProductId() + ":" + message.getToken();

        // Redis Sorted Set에 추가 (score = 요청 시간)
        redisTemplate.opsForZSet().add(QUEUE_KEY, queueValue, message.getTimestamp());

        log.info("Kafka -> Redis 대기열 등록 (Version C) - sessionId: {}, productId: {}, token: {}",
                message.getSessionId(), message.getProductId(), message.getToken());
    }

    /**
     * DLT (Dead Letter Topic) Handler
     *
     * 모든 재시도가 실패한 메시지가 여기로 옵니다.
     * @DltHandler는 @RetryableTopic과 같은 클래스에 있어야 합니다.
     *
     * 처리:
     * 1. Prometheus 카운터 증가 → Grafana/Datadog 알림 트리거
     * 2. ERROR 로그 → 운영자가 원인 파악 후 수동 재처리
     *
     * [Replay 방법]
     * DLT의 offset을 리셋하면 실패 메시지를 다시 읽을 수 있습니다.
     * kafka-consumer-groups --reset-offsets --to-earliest --topic queue-entry-requests.DLT
     */
    @DltHandler
    public void handleDlt(QueueEntryMessage message) {
        dltCounter.increment();

        log.error("[DLT] 대기열 등록 최종 실패 - sessionId: {}, productId: {}, token: {}, timestamp: {}",
                message.getSessionId(),
                message.getProductId(),
                message.getToken(),
                message.getTimestamp());

        log.error("[DLT] Replay 방법: kafka-consumer-groups --reset-offsets --to-earliest " +
                "--group {} --topic {} --execute",
                KafkaClusterConfig.CONSUMER_GROUP, KafkaClusterConfig.DLT_TOPIC);
    }
}
