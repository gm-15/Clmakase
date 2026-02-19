package com.oliveyoung.sale.controller;

import com.oliveyoung.sale.dto.*;
import com.oliveyoung.sale.service.QueueOperations;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/queue")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class QueueController {

    private final QueueOperations queueService;

    /**
     * 대기열 진입
     * POST /api/queue/enter
     *
     * [시연 포인트]
     * 상품 구매 버튼 클릭 시 호출
     * 응답의 token을 프론트에서 저장하고, 이후 status 조회에 사용
     */
    @PostMapping("/enter")
    public ApiResponse<QueueEntryResponse> enterQueue(
            @RequestHeader(value = "X-Session-Id", defaultValue = "demo-session") String sessionId,
            @Valid @RequestBody QueueEntryRequest request
    ) {
        QueueOperations.QueueEntry entry = queueService.enterQueue(sessionId, request.productId());

        QueueEntryResponse response = new QueueEntryResponse(
                entry.token(),
                entry.position(),
                entry.estimatedWaitSeconds(),
                String.format("대기열에 등록되었습니다. 현재 %d번째입니다.", entry.position())
        );

        return ApiResponse.success(response);
    }

    /**
     * 대기 상태 조회
     * GET /api/queue/status?productId={id}&token={token}
     *
     * [시연 포인트]
     * 프론트에서 2초 간격으로 Polling하여 순번 업데이트
     * canPurchase가 true가 되면 구매 페이지로 이동
     */
    @GetMapping("/status")
    public ApiResponse<QueueStatusResponse> getQueueStatus(
            @RequestHeader(value = "X-Session-Id", defaultValue = "demo-session") String sessionId,
            @RequestParam Long productId,
            @RequestParam String token
    ) {
        QueueOperations.QueueStatus status = queueService.getQueueStatus(sessionId, token, productId);

        String message;
        if (status.canPurchase()) {
            message = "구매가 가능합니다!";
        } else if (status.expired()) {
            message = "대기열이 만료되었습니다. 다시 시도해주세요.";
        } else {
            message = String.format("현재 %d번째입니다. 예상 대기 시간: %d초",
                    status.position(), status.estimatedWaitSeconds());
        }

        QueueStatusResponse response = new QueueStatusResponse(
                status.position(),
                status.estimatedWaitSeconds(),
                status.canPurchase(),
                status.expired(),
                message
        );

        return ApiResponse.success(response);
    }
}
