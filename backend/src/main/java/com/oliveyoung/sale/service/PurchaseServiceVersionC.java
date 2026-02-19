package com.oliveyoung.sale.service;

import com.oliveyoung.sale.dto.OrderEvent;
import com.oliveyoung.sale.dto.PurchaseRequest;
import com.oliveyoung.sale.dto.PurchaseResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;

/**
 * 구매 서비스 - Version C (비동기 처리)
 *
 * [Version A와의 차이]
 * Version A: API → DB 직접 INSERT (동기) → 응답
 * Version C: API → Kafka 발행 (비동기) → 즉시 202 Accepted → Consumer가 DB INSERT
 *
 * [왜 비동기인가?]
 * 세일 오픈 시 수천 건 동시 구매 → DB 직접 INSERT → 락 경합 + DB 과부하
 * Kafka가 버퍼 역할 → Consumer가 조절하며 INSERT → DB 안정
 * API 서버는 Kafka 발행 후 즉시 응답 → 사용자 경험 향상
 *
 * [주문 데이터 보호]
 * Kafka order-events 토픽 → Consumer 실패 시 Non-blocking Retry
 * → 모든 재시도 실패 → DLT(Dead Letter Topic)에 격리 보관
 * → Prometheus 메트릭으로 장애 감지 → offset 리셋으로 Replay
 *
 * [면접 포인트]
 * Q: "비동기면 사용자가 주문 완료 여부를 모르지 않나요?"
 * A: 202 Accepted + 주문 접수 메시지를 먼저 반환합니다.
 *    실제 운영에서는 WebSocket/SSE로 처리 완료를 알릴 수 있지만,
 *    시연용 MVP에서는 폴링 방식으로 주문 상태를 확인합니다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("version-c")
public class PurchaseServiceVersionC implements PurchaseOperations {

    private final QueueOperations queueService;
    private final KafkaClusterProducerService kafkaProducerService;

    @Override
    public PurchaseResponse purchase(String sessionId, String token, PurchaseRequest request) {
        Long productId = request.productId();
        int quantity = request.quantity();

        // 1. 대기열 상태 확인 (구매 가능 여부)
        QueueOperations.QueueStatus queueStatus = queueService.getQueueStatus(sessionId, token, productId);
        if (!queueStatus.canPurchase()) {
            throw new IllegalStateException("아직 구매할 수 없습니다. 대기열 순번: " + queueStatus.position());
        }

        // 2. Kafka에 주문 이벤트 비동기 발행
        OrderEvent event = new OrderEvent(
                sessionId,
                productId,
                quantity,
                token,
                System.currentTimeMillis()
        );
        kafkaProducerService.sendOrderEvent(event);

        log.info("주문 이벤트 Kafka 발행 (비동기) - sessionId: {}, productId: {}, quantity: {}",
                sessionId, productId, quantity);

        // 3. 즉시 응답 (실제 주문 처리는 OrderConsumerService가 비동기로 수행)
        return new PurchaseResponse(
                null,  // orderId는 Consumer가 DB INSERT 후 생성
                null,  // productName은 Consumer가 조회
                quantity,
                BigDecimal.ZERO,  // 최종 가격은 Consumer가 계산
                "주문이 접수되었습니다. 잠시 후 처리가 완료됩니다."
        );
    }
}
