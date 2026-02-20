package com.oliveyoung.sale.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.ZSetOperations;

import com.oliveyoung.sale.dto.QueueEntryMessage;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class QueueServiceTest {

    @Mock
    private RedisTemplate<String, Object> redisTemplate;

    @Mock
    private ZSetOperations<String, Object> zSetOperations;

    @Mock
    private SetOperations<String, Object> setOperations;

    @Mock
    private KafkaProducerService kafkaProducerService;

    @InjectMocks
    private QueueService queueService;

    @BeforeEach
    void setUp() {
        lenient().when(redisTemplate.opsForZSet()).thenReturn(zSetOperations);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOperations);
    }

    @Test
    @DisplayName("대기열 진입 성공")
    void enterQueue_success() {
        when(zSetOperations.size("purchase:queue")).thenReturn(50L);

        QueueService.QueueEntry result = queueService.enterQueue("session-1", 1L);

        assertThat(result.token()).isNotNull();
        assertThat(result.position()).isEqualTo(51);
        assertThat(result.estimatedWaitSeconds()).isEqualTo(6); // ceil(51/10)
        verify(kafkaProducerService).sendQueueEntry(any(QueueEntryMessage.class));
    }

    @Test
    @DisplayName("대기열 가득 찼을 때 예외 발생")
    void enterQueue_queueFull() {
        when(zSetOperations.size("purchase:queue")).thenReturn(10000L);

        assertThatThrownBy(() -> queueService.enterQueue("session-1", 1L))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("대기열이 가득 찼습니다");
    }

    @Test
    @DisplayName("처리 중 상태일 때 구매 가능")
    void getQueueStatus_canPurchase() {
        String queueValue = "session-1:1:token-abc";
        when(setOperations.isMember("purchase:processing", queueValue)).thenReturn(true);

        QueueService.QueueStatus result = queueService.getQueueStatus("session-1", "token-abc", 1L);

        assertThat(result.canPurchase()).isTrue();
        assertThat(result.position()).isEqualTo(0);
    }

    @Test
    @DisplayName("대기 중 상태")
    void getQueueStatus_waiting() {
        String queueValue = "session-1:1:token-abc";
        when(setOperations.isMember("purchase:processing", queueValue)).thenReturn(false);
        when(zSetOperations.rank("purchase:queue", queueValue)).thenReturn(4L);

        QueueService.QueueStatus result = queueService.getQueueStatus("session-1", "token-abc", 1L);

        assertThat(result.canPurchase()).isFalse();
        assertThat(result.position()).isEqualTo(5);
        assertThat(result.expired()).isFalse();
    }

    @Test
    @DisplayName("대기열에서 만료된 상태")
    void getQueueStatus_expired() {
        String queueValue = "session-1:1:token-abc";
        when(setOperations.isMember("purchase:processing", queueValue)).thenReturn(false);
        when(zSetOperations.rank("purchase:queue", queueValue)).thenReturn(null);

        QueueService.QueueStatus result = queueService.getQueueStatus("session-1", "token-abc", 1L);

        assertThat(result.canPurchase()).isFalse();
        assertThat(result.expired()).isTrue();
    }
}
