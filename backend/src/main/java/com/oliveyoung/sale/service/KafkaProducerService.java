package com.oliveyoung.sale.service;

import com.oliveyoung.sale.config.KafkaConfig;
import com.oliveyoung.sale.dto.QueueEntryMessage;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ZSetOperations;
import org.springframework.context.annotation.Profile;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.time.Duration;

/**
 * Kafka Producer 서비스 - Version A (Circuit Breaker 적용)
 *
 * [정상 흐름]  사용자 → Kafka Produce → Consumer → Redis ZADD
 * [장애 흐름]  사용자 → Kafka 실패 → Circuit Open → Redis ZADD 직접 (폴백)
 *
 * [Circuit Breaker 상태]
 *   CLOSED  → 정상 상태. Kafka로 전송
 *   OPEN    → 장애 감지. Redis 직접 ZADD로 폴백
 *   HALF_OPEN → 일부 요청을 Kafka로 시도하여 복구 확인
 *
 * [면접 포인트]
 * Q: "Kafka가 장애 나면 서비스 전체가 멈추나요?"
 * A: Circuit Breaker 패턴으로 자동 폴백합니다.
 *    연속 5회 실패 시 회로가 열리고, Redis에 직접 ZADD합니다.
 *    30초 후 Kafka 복구를 시도하며, 성공하면 다시 Kafka 경로로 전환됩니다.
 *    사용자는 장애를 인지하지 못합니다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("!version-c")
public class KafkaProducerService {

    private final KafkaTemplate<String, QueueEntryMessage> kafkaTemplate;
    private final RedisTemplate<String, Object> redisTemplate;

    private static final String QUEUE_KEY = "purchase:queue";
    private CircuitBreaker circuitBreaker;

    @PostConstruct
    public void init() {
        CircuitBreakerConfig config = CircuitBreakerConfig.custom()
                // 5회 실패 시 회로 열림
                .slidingWindowSize(5)
                .slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
                // 실패율 50% 이상이면 OPEN
                .failureRateThreshold(50)
                // OPEN 상태 30초 유지 후 HALF_OPEN 전환
                .waitDurationInOpenState(Duration.ofSeconds(30))
                // HALF_OPEN에서 3회 시도
                .permittedNumberOfCallsInHalfOpenState(3)
                .build();

        CircuitBreakerRegistry registry = CircuitBreakerRegistry.of(config);
        this.circuitBreaker = registry.circuitBreaker("kafka-producer");

        // 상태 변경 이벤트 로깅
        circuitBreaker.getEventPublisher()
                .onStateTransition(event ->
                        log.warn("Circuit Breaker 상태 변경: {}", event.getStateTransition()));
    }

    /**
     * 대기열 진입 요청 전송 (Circuit Breaker 적용)
     *
     * @param message 대기열 진입 메시지
     */
    public void sendQueueEntry(QueueEntryMessage message) {
        try {
            circuitBreaker.executeRunnable(() -> sendToKafka(message));
        } catch (Exception e) {
            // Circuit이 OPEN이거나 Kafka 전송 실패 → Redis 직접 폴백
            log.warn("Kafka 전송 불가, Redis 직접 ZADD 폴백 - sessionId: {}, reason: {}",
                    message.getSessionId(), e.getMessage());
            fallbackToRedis(message);
        }
    }

    /**
     * Kafka로 메시지 전송 (동기 방식 - Circuit Breaker 감지용)
     */
    private void sendToKafka(QueueEntryMessage message) {
        String partitionKey = String.valueOf(message.getProductId());

        try {
            // Circuit Breaker가 성공/실패를 감지할 수 있도록 동기 전송 (3초 타임아웃)
            SendResult<String, QueueEntryMessage> result =
                    kafkaTemplate.send(KafkaConfig.QUEUE_TOPIC, partitionKey, message)
                            .get(3, java.util.concurrent.TimeUnit.SECONDS);

            log.debug("Kafka 메시지 발행 성공 - topic: {}, partition: {}, offset: {}",
                    result.getRecordMetadata().topic(),
                    result.getRecordMetadata().partition(),
                    result.getRecordMetadata().offset());

        } catch (Exception e) {
            // 타임아웃, 전송 실패 등 → Circuit Breaker에 실패로 기록됨
            throw new RuntimeException("Kafka 전송 실패: " + e.getMessage(), e);
        }
    }

    /**
     * Redis 직접 ZADD 폴백
     *
     * Kafka가 장애 상태일 때 대기열 서비스가 중단되지 않도록
     * Redis에 직접 데이터를 적재합니다.
     *
     * Consumer가 하던 것과 동일한 로직:
     *   ZADD purchase:queue {timestamp} {sessionId:productId:token}
     */
    private void fallbackToRedis(QueueEntryMessage message) {
        try {
            ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();
            String queueValue = message.getSessionId() + ":" + message.getProductId() + ":" + message.getToken();

            zSetOps.add(QUEUE_KEY, queueValue, message.getTimestamp());

            log.info("Redis 직접 ZADD 폴백 성공 - sessionId: {}, productId: {}",
                    message.getSessionId(), message.getProductId());
        } catch (Exception redisEx) {
            // Redis도 실패하면 진짜 장애 → 로그 남기고 상위로 전파
            log.error("Redis 폴백도 실패! sessionId: {}, error: {}",
                    message.getSessionId(), redisEx.getMessage());
            throw new RuntimeException("Kafka와 Redis 모두 실패", redisEx);
        }
    }
}
