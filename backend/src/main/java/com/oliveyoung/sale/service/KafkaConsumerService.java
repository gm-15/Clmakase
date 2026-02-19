package com.oliveyoung.sale.service;

import com.oliveyoung.sale.config.KafkaConfig;
import com.oliveyoung.sale.dto.QueueEntryMessage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

/**
 * Kafka Consumer 서비스 - Version A (단일 브로커)
 *
 * Kafka 토픽에서 대기열 진입 메시지를 소비하여 Redis Sorted Set에 추가
 *
 * [흐름]
 * Kafka Topic (queue-entry-requests)
 *   → Consumer (이 서비스)
 *   → Redis ZADD purchase:queue {sessionId:productId:token} {timestamp}
 *
 * [장점]
 * 1. Kafka가 버퍼 역할 → 트래픽 폭증 시 앱 서버 보호
 * 2. Consumer 속도 조절로 Redis 부하 제어
 * 3. 장애 시 Kafka offset 기반 재처리 (이벤트 리플레이)
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("!version-c")
public class KafkaConsumerService {

    private static final String QUEUE_KEY = "purchase:queue";
    private final RedisTemplate<String, Object> redisTemplate;

    @KafkaListener(
            topics = KafkaConfig.QUEUE_TOPIC,
            groupId = KafkaConfig.CONSUMER_GROUP,
            containerFactory = "kafkaListenerContainerFactory"
    )
    public void consumeQueueEntry(QueueEntryMessage message) {
        try {
            String queueValue = message.getSessionId() + ":" + message.getProductId() + ":" + message.getToken();

            // Redis Sorted Set에 추가 (score = 요청 시간)
            redisTemplate.opsForZSet().add(QUEUE_KEY, queueValue, message.getTimestamp());

            log.info("Kafka -> Redis 대기열 등록 - sessionId: {}, productId: {}, token: {}",
                    message.getSessionId(), message.getProductId(), message.getToken());

        } catch (Exception e) {
            log.error("대기열 등록 실패 - sessionId: {}, error: {}",
                    message.getSessionId(), e.getMessage());
            // 실패 시 Kafka가 자동 재시도 (auto commit 비활성화)
            throw e;
        }
    }
}
