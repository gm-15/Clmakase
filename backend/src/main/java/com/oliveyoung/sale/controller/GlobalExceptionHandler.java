package com.oliveyoung.sale.controller;

import com.oliveyoung.sale.dto.ApiResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * 전역 예외 처리
 *
 * [면접 포인트]
 * Q: "예외 처리를 한 곳에서 하는 이유는?"
 * A: 1) 일관된 에러 응답 형식 보장
 *    2) 에러 로깅 중앙화
 *    3) 예외 타입별 HTTP 상태 코드 매핑
 *    4) 민감 정보 노출 방지 (스택 트레이스 숨김)
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    /**
     * 비즈니스 로직 예외 (잘못된 요청)
     */
    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResponse<Void> handleIllegalArgument(IllegalArgumentException e) {
        log.warn("잘못된 요청: {}", e.getMessage());
        return ApiResponse.error(e.getMessage(), "BAD_REQUEST");
    }

    /**
     * 비즈니스 로직 예외 (상태 오류)
     */
    @ExceptionHandler(IllegalStateException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public ApiResponse<Void> handleIllegalState(IllegalStateException e) {
        log.warn("상태 오류: {}", e.getMessage());
        return ApiResponse.error(e.getMessage(), "STATE_ERROR");
    }

    /**
     * 유효성 검사 실패
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResponse<Void> handleValidation(MethodArgumentNotValidException e) {
        String message = e.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + ": " + error.getDefaultMessage())
                .findFirst()
                .orElse("입력값이 올바르지 않습니다.");

        log.warn("유효성 검사 실패: {}", message);
        return ApiResponse.error(message, "VALIDATION_ERROR");
    }

    /**
     * 정적 리소스 없음 (favicon.ico 등)
     */
    @ExceptionHandler(NoResourceFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public void handleNoResource(NoResourceFoundException e) {
        // 404로 조용히 처리, 응답 바디 없음
    }

    /**
     * 기타 예외 (서버 오류)
     */
    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ApiResponse<Void> handleException(Exception e) {
        log.error("서버 오류 발생", e);
        // 프로덕션에서는 상세 메시지 노출 금지
        return ApiResponse.error("서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.", "INTERNAL_ERROR");
    }
}
