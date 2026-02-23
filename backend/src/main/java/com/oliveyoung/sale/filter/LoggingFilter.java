package com.oliveyoung.sale.filter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * HTTP 요청/응답 정보를 MDC(Mapped Diagnostic Context)에 주입하는 필터
 *
 * [동작 방식]
 *   요청 진입  → http.method, http.url, http.client_ip를 MDC에 등록
 *   컨트롤러/서비스 실행 (이 구간의 로그에 method·url 자동 포함)
 *   응답 완료  → http.status_code, http.duration_ms를 MDC에 추가 후 ACCESS LOG 1건 기록
 *   finally   → MDC.clear() (다음 요청 오염 방지)
 *
 * [Datadog 인덱싱 연동]
 *   - 이 필터가 찍는 ACCESS LOG(level=INFO/WARN)를 기준으로 Datadog 파이프라인이 Drop/Index 결정
 *   - status_code 2xx + duration_ms < 3000 → Datadog에서 Drop (비용 절감)
 *   - status_code 4xx/5xx OR duration_ms >= 3000 → Datadog에서 100% Index (트러블슈팅)
 *   - 서비스 레이어 ERROR 로그 → Datadog 파이프라인에서 level:error 조건으로 100% Index
 *
 * [MDC 필드 목록]
 *   http.method      : GET, POST 등
 *   http.url         : 요청 URI (/api/v1/products 등)
 *   http.status_code : 응답 상태 코드 (200, 404, 500 등)
 *   http.duration_ms : 요청 처리 소요 시간 (밀리초)
 *   http.client_ip   : 클라이언트 실제 IP (X-Forwarded-For 헤더 우선)
 */
@Slf4j
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class LoggingFilter extends OncePerRequestFilter {

    /** 3초 이상 소요되면 WARN 레벨로 찍어서 Datadog에서 Index 대상이 되게 함 */
    private static final long SLOW_THRESHOLD_MS = 3000L;

    /** Actuator health check는 Datadog에 불필요한 노이즈 → 로깅 생략 */
    private static final String HEALTH_CHECK_URI = "/actuator/health";

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {

        // Actuator health check는 MDC 등록 및 로깅 생략
        if (HEALTH_CHECK_URI.equals(request.getRequestURI())) {
            filterChain.doFilter(request, response);
            return;
        }

        long startTime = System.currentTimeMillis();

        // ── 요청 수신 시점: 요청 정보를 MDC에 등록 ────────────────────────────
        // 이후 모든 서비스/레포지토리 로그에 아래 필드가 자동으로 포함됨
        MDC.put("http.method", request.getMethod());
        MDC.put("http.url", request.getRequestURI());
        MDC.put("http.client_ip", resolveClientIp(request));

        try {
            filterChain.doFilter(request, response);

        } finally {
            // ── 응답 완료 시점: 상태 코드 + 소요 시간 추가 ──────────────────────
            long durationMs = System.currentTimeMillis() - startTime;
            int statusCode = response.getStatus();

            MDC.put("http.status_code", String.valueOf(statusCode));
            MDC.put("http.duration_ms", String.valueOf(durationMs));

            // ACCESS LOG: 요청 1건당 1개 기록
            // - 2xx + 3초 미만 → INFO (Datadog에서 Drop 처리)
            // - 4xx/5xx 또는 3초 이상 → WARN (Datadog에서 Index 처리)
            if (statusCode >= 400 || durationMs >= SLOW_THRESHOLD_MS) {
                log.warn("[ACCESS] {} {} → {} ({}ms)",
                        request.getMethod(), request.getRequestURI(), statusCode, durationMs);
            } else {
                log.info("[ACCESS] {} {} → {} ({}ms)",
                        request.getMethod(), request.getRequestURI(), statusCode, durationMs);
            }

            // 요청 종료 후 MDC 초기화 (쓰레드 재사용 시 이전 요청 값 오염 방지)
            MDC.clear();
        }
    }

    /**
     * 실제 클라이언트 IP 추출
     * ALB/CDN 뒤에서는 X-Forwarded-For 헤더에 실제 IP가 들어옴
     */
    private String resolveClientIp(HttpServletRequest request) {
        String xForwardedFor = request.getHeader("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isBlank()) {
            // X-Forwarded-For: client, proxy1, proxy2 → 첫 번째가 실제 클라이언트
            return xForwardedFor.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
