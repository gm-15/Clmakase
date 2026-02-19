package com.oliveyoung.sale.service;

import com.oliveyoung.sale.config.KafkaClusterConfig;
import com.oliveyoung.sale.domain.Product;
import com.oliveyoung.sale.domain.PurchaseOrder;
import com.oliveyoung.sale.dto.OrderEvent;
import com.oliveyoung.sale.repository.ProductRepository;
import com.oliveyoung.sale.repository.PurchaseOrderRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.kafka.annotation.DltHandler;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.annotation.RetryableTopic;
import org.springframework.kafka.retrytopic.DltStrategy;
import org.springframework.kafka.retrytopic.TopicSuffixingStrategy;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.retry.annotation.Backoff;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

/**
 * 주문 처리 Consumer - Version C (Non-blocking Retry + DLT)
 *
 * [이 코드는 "개발"이 아니라 "인프라 설계"입니다]
 * 주문 로직 자체는 DB INSERT 한 줄.
 * 진짜 보여주는 것은:
 *   1. 장애 시 데이터 보호 (DLT)
 *   2. 장애 격리 (Non-blocking Retry)
 *   3. 장애 감지 (Prometheus 메트릭 → Grafana/Datadog 알림)
 *   4. 장애 복구 (offset Replay)
 *
 * [메시지 흐름 + 모니터링 의미]
 *
 *   order-events (정상 처리)
 *     → order_success_total ↑             ← 시스템 정상
 *
 *   order-events (실패)
 *     → order-events-retry-0 (1초 후)
 *       → order_retry_total{stage="0"} ↑  ← 일시적 장애 (네트워크 지연, GC pause)
 *
 *     → order-events-retry-1 (5초 후)
 *       → order_retry_total{stage="1"} ↑  ← DB 커넥션 풀 부족, Aurora Failover 중
 *
 *     → order-events-retry-2 (30초 후)
 *       → order_retry_total{stage="2"} ↑  ← DB 장시간 응답 없음, Pod 재시작 중
 *
 *     → order-events.DLT
 *       → order_dlt_total ↑               ← 심각한 장애. 즉시 대응 필요
 *
 * [면접 포인트]
 * Q: "retry 단계별로 나눈 이유?"
 * A: 각 단계가 다른 장애 신호를 줍니다.
 *    retry-0만 증가 → 네트워크 순간 지연 (자동 복구, 무시 가능)
 *    retry-1까지 → DB 커넥션 이슈 (경고 알림)
 *    retry-2까지 → DB 장시간 장애 (위험 알림, 운영자 확인)
 *    DLT → 복구 불가 (긴급 대응, 수동 Replay)
 *    Grafana 대시보드에서 어떤 단계가 증가하는지 보면
 *    인프라의 어느 구간에 병목이 있는지 즉시 파악됩니다.
 *
 * Q: "Kafka 토픽을 두 개로 나눈 이유?"
 * A: 데이터의 중요도가 다릅니다.
 *    queue-entry-requests: 대기열 진입 → 유실돼도 재시도 가능
 *    order-events: 주문 확정 → 유실 = 매출 손실
 *    주문 토픽에만 DLT를 적용하여 인프라 비용 대비 보호 효과 극대화.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("version-c")
public class OrderConsumerService {

    private final ProductRepository productRepository;
    private final PurchaseOrderRepository orderRepository;
    private final QueueOperations queueService;
    private final SaleStateService saleStateService;
    private final MeterRegistry meterRegistry;

    private Counter orderDltCounter;
    private Counter orderSuccessCounter;
    private Counter retryStage0Counter;
    private Counter retryStage1Counter;
    private Counter retryStage2Counter;

    @PostConstruct
    public void init() {
        orderSuccessCounter = Counter.builder("order_success_total")
                .description("Successfully processed orders")
                .register(meterRegistry);

        orderDltCounter = Counter.builder("order_dlt_total")
                .description("Orders sent to DLT (all retries failed)")
                .register(meterRegistry);

        // retry 단계별 카운터 → Grafana에서 어느 단계에서 장애가 해소되는지 파악
        retryStage0Counter = Counter.builder("order_retry_total")
                .tag("stage", "0")
                .description("Orders retried at stage 0 (1s delay - network jitter)")
                .register(meterRegistry);

        retryStage1Counter = Counter.builder("order_retry_total")
                .tag("stage", "1")
                .description("Orders retried at stage 1 (5s delay - DB connection issue)")
                .register(meterRegistry);

        retryStage2Counter = Counter.builder("order_retry_total")
                .tag("stage", "2")
                .description("Orders retried at stage 2 (30s delay - severe infra issue)")
                .register(meterRegistry);
    }

    /**
     * 주문 이벤트 Consumer (Non-blocking Retry + DLT)
     *
     * @RetryableTopic 동작:
     * - attempts = 4 → 최초 1회 + 재시도 3회
     * - 실패 → retry 토픽으로 메시지 발행 → 원본 파티션은 계속 처리 (Non-blocking)
     * - 1초(retry-0) → 5초(retry-1) → 30초(retry-2) → DLT
     *
     * @param event 주문 이벤트
     * @param receivedTopic 현재 소비 중인 토픽 이름 (retry 단계 판단용)
     */
    @RetryableTopic(
            attempts = "4",
            backoff = @Backoff(delay = 1000, multiplier = 5, maxDelay = 30000),
            topicSuffixingStrategy = TopicSuffixingStrategy.SUFFIX_WITH_INDEX_VALUE,
            dltStrategy = DltStrategy.ALWAYS_RETRY_ON_ERROR,
            include = Exception.class
    )
    @KafkaListener(
            topics = KafkaClusterConfig.ORDER_TOPIC,
            groupId = KafkaClusterConfig.ORDER_CONSUMER_GROUP
    )
    @Transactional
    public void consumeOrderEvent(
            OrderEvent event,
            @Header(KafkaHeaders.RECEIVED_TOPIC) String receivedTopic) {

        // retry 단계별 메트릭 기록
        trackRetryStage(receivedTopic);

        log.info("주문 처리 시작 - sessionId: {}, productId: {}, topic: {}",
                event.getSessionId(), event.getProductId(), receivedTopic);

        // 1. 상품 조회 (비관적 락)
        Product product = productRepository.findByIdWithLock(event.getProductId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "상품을 찾을 수 없습니다. productId: " + event.getProductId()));

        // 2. 재고 차감
        product.decreaseStock(event.getQuantity());

        // 3. 가격 계산
        boolean isSaleActive = saleStateService.isSaleActive();
        BigDecimal unitPrice = isSaleActive ? product.getDiscountedPrice() : product.getOriginalPrice();
        BigDecimal totalPrice = unitPrice.multiply(BigDecimal.valueOf(event.getQuantity()));

        // 4. 주문 생성
        PurchaseOrder order = PurchaseOrder.builder()
                .sessionId(event.getSessionId())
                .product(product)
                .quantity(event.getQuantity())
                .totalPrice(totalPrice)
                .status(PurchaseOrder.OrderStatus.COMPLETED)
                .build();

        PurchaseOrder savedOrder = orderRepository.save(order);

        // 5. 대기열에서 제거
        queueService.completeProcessing(event.getSessionId(), event.getToken(), event.getProductId());

        // 6. 성공 메트릭
        orderSuccessCounter.increment();

        log.info("주문 처리 완료 - orderId: {}, totalPrice: {}, topic: {}",
                savedOrder.getId(), totalPrice, receivedTopic);
    }

    /**
     * retry 토픽 이름에서 단계를 추출하여 메트릭 기록
     *
     * 토픽 이름 패턴:
     *   order-events           → 최초 시도 (메트릭 기록 안 함)
     *   order-events-retry-0   → 1차 재시도 (stage=0)
     *   order-events-retry-1   → 2차 재시도 (stage=1)
     *   order-events-retry-2   → 3차 재시도 (stage=2)
     */
    private void trackRetryStage(String topic) {
        if (topic.endsWith("-retry-0")) {
            retryStage0Counter.increment();
            log.warn("[RETRY-0] 1차 재시도 (1초 후) - 일시적 장애 가능성. topic: {}", topic);
        } else if (topic.endsWith("-retry-1")) {
            retryStage1Counter.increment();
            log.warn("[RETRY-1] 2차 재시도 (5초 후) - DB 커넥션 이슈 가능성. topic: {}", topic);
        } else if (topic.endsWith("-retry-2")) {
            retryStage2Counter.increment();
            log.error("[RETRY-2] 3차 재시도 (30초 후) - 심각한 인프라 장애 가능성. topic: {}", topic);
        }
    }

    /**
     * DLT Handler — 모든 재시도 실패 후 최종 도달
     *
     * [운영 대응 절차]
     * 1. Prometheus order_dlt_total 증가 → Grafana 알림 발생
     * 2. 운영자가 DLT 토픽 메시지 확인 → 장애 원인 파악
     *    - DB 다운? → Aurora Failover 확인
     *    - 재고 부족? → 비즈니스 이슈, 재입고 후 재처리
     *    - 코드 버그? → 핫픽스 배포 후 재처리
     * 3. 원인 해결 후 offset 리셋으로 Replay:
     *    kafka-consumer-groups --reset-offsets --to-earliest
     *      --group order-processor-group --topic order-events.DLT --execute
     */
    @DltHandler
    public void handleOrderDlt(OrderEvent event) {
        orderDltCounter.increment();

        log.error("[ORDER-DLT] 주문 처리 최종 실패 - sessionId: {}, productId: {}, quantity: {}, timestamp: {}",
                event.getSessionId(),
                event.getProductId(),
                event.getQuantity(),
                event.getTimestamp());

        log.error("[ORDER-DLT] 이 데이터는 고객의 구매 의사가 확정된 주문입니다. " +
                "원인 파악 후 반드시 재처리하세요.");
    }
}
