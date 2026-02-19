package com.oliveyoung.sale.service;

import com.oliveyoung.sale.domain.Product;
import com.oliveyoung.sale.domain.PurchaseOrder;
import com.oliveyoung.sale.dto.PurchaseRequest;
import com.oliveyoung.sale.dto.PurchaseResponse;
import com.oliveyoung.sale.repository.ProductRepository;
import com.oliveyoung.sale.repository.PurchaseOrderRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

/**
 * 구매 서비스 - Version A (동기 처리)
 *
 * API 요청 → DB 직접 INSERT (동기)
 *
 * [면접 포인트]
 * Q: "동시에 수천 명이 구매하면 어떻게 되나요?"
 * A: 1) 대기열로 동시 접근 제어 (초당 10명씩 순차 처리)
 *    2) 비관적 락으로 재고 정합성 보장
 *    3) 트랜잭션으로 원자성 보장
 *
 *    대기열이 없으면 모든 요청이 DB로 몰려 락 경합 발생,
 *    응답 시간 급증, 타임아웃, 데드락 위험이 있습니다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("!version-c")
public class PurchaseService implements PurchaseOperations {

    private final ProductRepository productRepository;
    private final PurchaseOrderRepository orderRepository;
    private final ProductService productService;
    private final QueueOperations queueService;
    private final SaleStateService saleStateService;

    /**
     * 구매 처리
     *
     * [면접 포인트]
     * Q: "결제 실패하면 재고는 어떻게 되나요?"
     * A: @Transactional로 전체 롤백됩니다.
     *    재고 차감 -> 주문 생성 -> (결제 연동) 순서에서
     *    중간에 실패하면 모든 변경이 취소됩니다.
     *
     *    실제 결제 연동 시에는 보상 트랜잭션(Saga 패턴)이나
     *    2PC를 고려해야 하지만, 시연용 MVP에서는 생략합니다.
     */
    @Transactional
    public PurchaseResponse purchase(String sessionId, String token, PurchaseRequest request) {
        Long productId = request.productId();
        int quantity = request.quantity();

        // 1. 대기열 상태 확인 (구매 가능 여부)
        QueueOperations.QueueStatus queueStatus = queueService.getQueueStatus(sessionId, token, productId);
        if (!queueStatus.canPurchase()) {
            throw new IllegalStateException("아직 구매할 수 없습니다. 대기열 순번: " + queueStatus.position());
        }

        // 2. 상품 조회 (비관적 락)
        Product product = productRepository.findByIdWithLock(productId)
                .orElseThrow(() -> new IllegalArgumentException("상품을 찾을 수 없습니다."));

        // 3. 재고 확인 및 차감
        product.decreaseStock(quantity);

        // 4. 최종 가격 계산 (서버에서 재계산 - 보안)
        boolean isSaleActive = saleStateService.isSaleActive();
        BigDecimal unitPrice = isSaleActive ? product.getDiscountedPrice() : product.getOriginalPrice();
        BigDecimal totalPrice = unitPrice.multiply(BigDecimal.valueOf(quantity));

        // 5. 주문 생성
        PurchaseOrder order = PurchaseOrder.builder()
                .sessionId(sessionId)
                .product(product)
                .quantity(quantity)
                .totalPrice(totalPrice)
                .status(PurchaseOrder.OrderStatus.COMPLETED)
                .build();

        PurchaseOrder savedOrder = orderRepository.save(order);

        // 6. 대기열에서 제거
        queueService.completeProcessing(sessionId, token, productId);

        log.info("구매 완료 - orderId: {}, productId: {}, quantity: {}, totalPrice: {}",
                savedOrder.getId(), productId, quantity, totalPrice);

        return new PurchaseResponse(
                savedOrder.getId(),
                product.getName(),
                quantity,
                totalPrice,
                "구매가 완료되었습니다!"
        );
    }
}
