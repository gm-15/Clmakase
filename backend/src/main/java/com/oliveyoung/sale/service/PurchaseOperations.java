package com.oliveyoung.sale.service;

import com.oliveyoung.sale.dto.PurchaseRequest;
import com.oliveyoung.sale.dto.PurchaseResponse;

/**
 * 구매 서비스 인터페이스
 *
 * Version A: PurchaseService (동기 - API → DB 직접 INSERT)
 * Version C: PurchaseServiceVersionC (비동기 - API → Kafka → Consumer → DB)
 *
 * Spring Profile로 런타임에 구현체 전환
 */
public interface PurchaseOperations {
    PurchaseResponse purchase(String sessionId, String token, PurchaseRequest request);
}
