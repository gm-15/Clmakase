package com.oliveyoung.sale.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.*;
import org.springframework.kafka.listener.ContainerProperties;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import org.springframework.kafka.support.serializer.JsonSerializer;

import java.util.HashMap;
import java.util.Map;

/**
 * Kafka 클러스터 설정 - Version C (3-Broker + Non-blocking Retry + DLT)
 *
 * [2개 토픽 전략]
 * 1. queue-entry-requests: 대기열 트래픽 버퍼링 (유실 OK → 사용자 재시도)
 * 2. order-events: 주문 처리 비동기화 (유실 불가 → DLT 보호 필수)
 *
 * [면접 포인트]
 * Q: "왜 토픽을 나눴나요?"
 * A: 데이터의 중요도가 다릅니다.
 *    대기열 진입은 유실돼도 사용자가 재시도하면 되지만,
 *    주문 확정은 유실 = 매출 손실입니다.
 *    주문 토픽에만 @RetryableTopic + DLT를 적용하여
 *    인프라 비용 대비 데이터 보호 효과를 극대화했습니다.
 *
 * Q: "SQS 대신 Kafka를 선택한 이유?"
 * A: 1) Non-blocking Retry: SQS DLQ는 Blocking, Kafka DLT는 Non-blocking
 *    2) Replay: Kafka는 offset 리셋으로 과거 데이터 재처리 가능
 *    3) 이식성: SQS는 AWS 전용, Kafka는 멀티 클라우드/온프레미스 호환
 */
@Configuration
@Profile("version-c")
public class KafkaClusterConfig {

    @Value("${spring.kafka.bootstrap-servers:localhost:9092}")
    private String bootstrapServers;

    // 대기열 토픽 (트래픽 버퍼링)
    public static final String QUEUE_TOPIC = "queue-entry-requests";
    public static final String DLT_TOPIC = "queue-entry-requests.DLT";
    public static final String CONSUMER_GROUP = "queue-processor-group";

    // 주문 토픽 (DLT가 진짜 의미 있는 곳 - 유실 불가 데이터)
    public static final String ORDER_TOPIC = "order-events";
    public static final String ORDER_DLT_TOPIC = "order-events.DLT";
    public static final String ORDER_CONSUMER_GROUP = "order-processor-group";

    // --- Topic 생성 (retry/DLT 토픽은 @RetryableTopic이 자동 생성) ---

    @Bean
    public NewTopic queueEntryTopic() {
        return TopicBuilder.name(QUEUE_TOPIC)
                .partitions(3)
                .replicas(3)
                .config("min.insync.replicas", "2")
                .build();
    }

    @Bean
    public NewTopic orderEventsTopic() {
        return TopicBuilder.name(ORDER_TOPIC)
                .partitions(3)
                .replicas(3)
                .config("min.insync.replicas", "2")
                .build();
    }

    // --- Producer 설정 (Object 타입으로 QueueEntryMessage, OrderEvent 모두 처리) ---

    @Bean
    public ProducerFactory<String, Object> producerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, 3);
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    public KafkaTemplate<String, Object> kafkaTemplate() {
        return new KafkaTemplate<>(producerFactory());
    }

    // --- Consumer 설정 ---

    @Bean
    public ConsumerFactory<String, Object> consumerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, CONSUMER_GROUP);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);
        props.put(JsonDeserializer.TRUSTED_PACKAGES, "com.oliveyoung.sale.dto");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        return new DefaultKafkaConsumerFactory<>(props);
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object> kafkaListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
                new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory());
        factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.RECORD);
        return factory;
    }
}
