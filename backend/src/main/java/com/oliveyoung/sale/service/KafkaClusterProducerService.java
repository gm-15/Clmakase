package com.oliveyoung.sale.service;

import com.oliveyoung.sale.config.KafkaClusterConfig;
import com.oliveyoung.sale.dto.OrderEvent;
import com.oliveyoung.sale.dto.QueueEntryMessage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

/**
 * Kafka Producer 서비스 - Version C (클러스터 + DLT)
 *
 * 2개 토픽에 메시지를 발행합니다:
 * 1. queue-entry-requests: 대기열 진입 (트래픽 버퍼링)
 * 2. order-events: 주문 확정 (데이터 무손실 필수)
 *
 * [면접 포인트]
 * Q: "Kafka 전송 실패하면 어떻게 되나요?"
 * A: 1) Producer 자체 재시도 (retries=3, 멱등성 보장)
 *    2) 3개 브로커 중 리더 장애 시 다른 브로커가 리더 승격
 *    3) Consumer 측에서 Non-blocking Retry 후에도 실패하면 DLT로 이동
 *    4) 주문 DLT 메시지는 운영자가 확인 후 offset 리셋으로 Replay
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Profile("version-c")
public class KafkaClusterProducerService {

    private final KafkaTemplate<String, Object> kafkaTemplate;

    /**
     * 대기열 진입 요청을 Kafka 클러스터에 비동기 전송
     */
    public void sendQueueEntry(QueueEntryMessage message) {
        String partitionKey = String.valueOf(message.getProductId());

        kafkaTemplate.send(KafkaClusterConfig.QUEUE_TOPIC, partitionKey, message)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        log.error("대기열 메시지 발행 실패 - sessionId: {}, error: {}",
                                message.getSessionId(), ex.getMessage());
                    } else {
                        log.debug("대기열 메시지 발행 성공 - topic: {}, partition: {}, offset: {}",
                                result.getRecordMetadata().topic(),
                                result.getRecordMetadata().partition(),
                                result.getRecordMetadata().offset());
                    }
                });
    }

    /**
     * 주문 이벤트를 Kafka 클러스터에 비동기 전송
     *
     * 이 메시지가 유실되면 매출 손실이므로 acks=all + replication=3으로 보호
     */
    public void sendOrderEvent(OrderEvent event) {
        String partitionKey = String.valueOf(event.getProductId());

        kafkaTemplate.send(KafkaClusterConfig.ORDER_TOPIC, partitionKey, event)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        log.error("주문 이벤트 발행 실패 - sessionId: {}, productId: {}, error: {}",
                                event.getSessionId(), event.getProductId(), ex.getMessage());
                    } else {
                        log.info("주문 이벤트 발행 성공 - topic: {}, partition: {}, offset: {}",
                                result.getRecordMetadata().topic(),
                                result.getRecordMetadata().partition(),
                                result.getRecordMetadata().offset());
                    }
                });
    }
}
