package com.oliveyoung.sale.dto;

import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 주문 이벤트 메시지 (Kafka order-events 토픽용)
 *
 * [메시지 흐름]
 * 구매 확정 API → Kafka (order-events) → OrderConsumer → Aurora DB INSERT
 *
 * [면접 포인트]
 * Q: "주문을 왜 Kafka를 통해 비동기로 처리하나요?"
 * A: 세일 오픈 시 수천 건의 동시 구매 요청이 DB로 직접 들어가면
 *    락 경합(Lock Contention)으로 DB가 과부하됩니다.
 *    Kafka가 버퍼 역할을 하여 Consumer가 초당 N건씩 조절하며
 *    DB에 INSERT합니다. API 서버는 Kafka에 발행 후 즉시 202 Accepted를
 *    반환하므로 사용자 응답 시간도 빨라집니다.
 *
 * Q: "주문 데이터가 유실되면?"
 * A: @RetryableTopic Non-blocking Retry로 3회 재시도하고,
 *    모든 재시도 실패 시 DLT(Dead Letter Topic)에 격리 보관됩니다.
 *    DLT의 메시지 수를 Prometheus 메트릭으로 모니터링하여
 *    장애를 조기 감지하고, offset 리셋으로 Replay할 수 있습니다.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class OrderEvent {
    private String sessionId;
    private Long productId;
    private Integer quantity;
    private String token;
    private long timestamp;
}
