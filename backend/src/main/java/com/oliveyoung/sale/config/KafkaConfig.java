package com.oliveyoung.sale.config;

import com.oliveyoung.sale.dto.QueueEntryMessage;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.core.*;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import org.springframework.kafka.support.serializer.JsonSerializer;

import org.springframework.context.annotation.Profile;

import java.util.HashMap;
import java.util.Map;

/**
 * Kafka 설정 - Version A (Circuit Breaker + 단일 브로커)
 *
 * [아키텍처]
 * Producer: 대기열 진입 요청을 Kafka 토픽에 발행
 * Consumer: 토픽에서 메시지를 소비하여 Redis Sorted Set에 ZADD
 *
 * [역할 분리]
 * Kafka = 트래픽 버퍼 (시스템 보호)
 * Redis ZSET = 순서 관리 (실시간 순위 조회)
 */
@Configuration
@Profile("!version-c")
public class KafkaConfig {

    @Value("${spring.kafka.bootstrap-servers:localhost:9092}")
    private String bootstrapServers;

    public static final String QUEUE_TOPIC = "queue-entry-requests";
    public static final String CONSUMER_GROUP = "queue-processor-group";

    // --- Producer 설정 ---
    @Bean
    public ProducerFactory<String, QueueEntryMessage> producerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        // 메시지 유실 방지
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, 3);
        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    public KafkaTemplate<String, QueueEntryMessage> kafkaTemplate() {
        return new KafkaTemplate<>(producerFactory());
    }

    // --- Consumer 설정 ---
    @Bean
    public ConsumerFactory<String, QueueEntryMessage> consumerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, CONSUMER_GROUP);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);
        props.put(JsonDeserializer.TRUSTED_PACKAGES, "com.oliveyoung.sale.dto");
        // 장애 복구 시 중복 방지
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        return new DefaultKafkaConsumerFactory<>(props);
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, QueueEntryMessage> kafkaListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactory<String, QueueEntryMessage> factory =
                new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory());
        // 수동 커밋 (메시지 처리 완료 후 커밋)
        factory.getContainerProperties().setAckMode(
                org.springframework.kafka.listener.ContainerProperties.AckMode.RECORD);
        return factory;
    }
}
