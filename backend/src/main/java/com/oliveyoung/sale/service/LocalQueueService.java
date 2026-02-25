package com.oliveyoung.sale.service;

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
 * 로컬 개발용 대기열 서비스 (Kafka 없이 Redis 직접 사용)
 */
@Slf4j
@Service
@Profile("local")
@RequiredArgsConstructor
public class LocalQueueService implements QueueOperations {

    private static final String QUEUE_KEY = "purchase:queue";
    private static final String PROCESSING_KEY = "purchase:processing";
    private static final int BATCH_SIZE = 10;

    private final RedisTemplate<String, Object> redisTemplate;

    @Override
    public QueueEntry enterQueue(String sessionId, Long productId) {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();

        String token = UUID.randomUUID().toString();
        long timestamp = System.currentTimeMillis();
        String queueValue = sessionId + ":" + productId + ":" + token;

        // Kafka 없이 Redis Sorted Set에 직접 추가
        zSetOps.add(QUEUE_KEY, queueValue, timestamp);

        Long rank = zSetOps.rank(QUEUE_KEY, queueValue);
        int position = (rank != null) ? rank.intValue() + 1 : 1;

        log.info("[Local] 대기열 직접 진입 - sessionId: {}, position: {}", sessionId, position);
        return new QueueEntry(token, position, estimateWaitTime(position));
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

    @Override
    public void completeProcessing(String sessionId, String token, Long productId) {
        String queueValue = sessionId + ":" + productId + ":" + token;
        redisTemplate.opsForSet().remove(PROCESSING_KEY, queueValue);
        log.info("[Local] 구매 완료 처리 - sessionId: {}", sessionId);
    }

    @Scheduled(fixedRate = 3000)
    public void processQueue() {
        ZSetOperations<String, Object> zSetOps = redisTemplate.opsForZSet();
        Set<Object> nextUsers = zSetOps.range(QUEUE_KEY, 0, BATCH_SIZE - 1);
        if (nextUsers == null || nextUsers.isEmpty()) return;

        for (Object user : nextUsers) {
            zSetOps.remove(QUEUE_KEY, user);
            redisTemplate.opsForSet().add(PROCESSING_KEY, user);
        }
        log.debug("[Local] 대기열 처리: {}명", nextUsers.size());
    }

    private int estimateWaitTime(int position) {
        // 3초마다 10명 처리 → 1명당 약 0.3초, position 기준 3초 단위 반올림
        return (int) Math.ceil(position / 10.0) * 3;
    }
}
