package com.oliveyoung.sale.controller;

import com.oliveyoung.sale.dto.ApiResponse;
import com.oliveyoung.sale.dto.PurchaseRequest;
import com.oliveyoung.sale.dto.PurchaseResponse;
import com.oliveyoung.sale.service.PurchaseOperations;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/purchase")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class PurchaseController {

    private final PurchaseOperations purchaseService;

    /**
     * 구매 처리
     * POST /api/purchase
     *
     * [시연 포인트]
     * 대기열에서 canPurchase가 true가 된 후 호출
     * 성공 시 구매 완료 페이지로 이동
     */
    @PostMapping
    public ApiResponse<PurchaseResponse> purchase(
            @RequestHeader(value = "X-Session-Id", defaultValue = "demo-session") String sessionId,
            @Valid @RequestBody PurchaseRequest request
    ) {
        PurchaseResponse response = purchaseService.purchase(sessionId, request.token(), request);
        return ApiResponse.success(response);
    }
}
