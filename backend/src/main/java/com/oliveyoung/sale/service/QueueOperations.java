package com.oliveyoung.sale.service;

/**
 * 대기열 서비스 인터페이스
 *
 * Version A (Circuit Breaker + 단일 브로커)와
 * Version C (Kafka 클러스터 + DLQ)가 이 인터페이스를 구현합니다.
 *
 * Spring Profile로 런타임에 구현체 전환:
 *   - 기본(Profile 없음): QueueService (Version A)
 *   - version-c Profile: QueueServiceVersionC (Version C)
 */
public interface QueueOperations {

    record QueueEntry(String token, int position, int estimatedWaitSeconds) {}
    record QueueStatus(int position, int estimatedWaitSeconds, boolean canPurchase, boolean expired) {}

    QueueEntry enterQueue(String sessionId, Long productId);
    QueueStatus getQueueStatus(String sessionId, String token, Long productId);
    void completeProcessing(String sessionId, String token, Long productId);
}
