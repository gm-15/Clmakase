import http from 'k6/http';
import { check, sleep } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

/**
 * 올리브영 대규모 세일 부하 테스트
 *
 * 실행 방법:
 *   k6 run k6/load-test.js
 *   k6 run --env BASE_URL=http://localhost:8080 k6/load-test.js
 */
export const options = {
    stages: [
        { duration: '30s', target: 100 },  // 30초 동안 0 → 100명 (워밍업)
        { duration: '1m',  target: 100 },  // 1분간 100명 유지 → KEDA Kafka lag 트리거 유도
        { duration: '30s', target: 300 },  // 30초 동안 100 → 300명 (피크 부하)
        { duration: '2m',  target: 300 },  // 2분간 300명 유지 → Karpenter 노드 추가 유도
        { duration: '30s', target: 0 },    // 30초 동안 300 → 0명 (쿨다운)
    ],
    thresholds: {
        http_req_duration: ['p(95)<2000'], // 95% 요청이 2000ms 이내 (스케일아웃 고려)
        http_req_failed: ['rate<0.1'],     // 에러율 10% 미만
    },
};

const BASE_URL = __ENV.BASE_URL || 'https://api.clmakase.click';

export default function () {
    const sessionId = `k6-vu-${__VU}-${__ITER}`;
    const headers = {
        'Content-Type': 'application/json',
        'X-Session-Id': sessionId,
    };

    // Step 1: 세일 상태 확인
    let res = http.get(`${BASE_URL}/api/sale/status`);
    check(res, { '세일 상태 조회 성공': (r) => r.status === 200 });

    // Step 2: 상품 목록 조회
    res = http.get(`${BASE_URL}/api/products`);
    check(res, { '상품 목록 조회 성공': (r) => r.status === 200 });

    // Step 3: 상품 상세 조회 (랜덤 1~8)
    const productId = Math.floor(Math.random() * 8) + 1;
    res = http.get(`${BASE_URL}/api/products/${productId}`);
    check(res, { '상품 상세 조회 성공': (r) => r.status === 200 });

    sleep(1);

    // Step 4: 대기열 진입
    res = http.post(
        `${BASE_URL}/api/queue/enter`,
        JSON.stringify({ productId: productId }),
        { headers: headers }
    );
    check(res, { '대기열 진입 성공': (r) => r.status === 200 });

    let token = '';
    try {
        const body = JSON.parse(res.body);
        if (body.data && body.data.token) {
            token = body.data.token;
        }
    } catch (e) {}

    // Step 5: 대기열 상태 폴링 (최대 5회, 2초 간격)
    let canPurchase = false;
    for (let i = 0; i < 5; i++) {
        sleep(2);
        res = http.get(
            `${BASE_URL}/api/queue/status?productId=${productId}&token=${token}`,
            { headers: headers }
        );
        check(res, { '대기열 상태 조회 성공': (r) => r.status === 200 });

        try {
            const status = JSON.parse(res.body);
            if (status.data && status.data.canPurchase) {
                canPurchase = true;
                break;
            }
        } catch (e) {}
    }

    // Step 6: 구매 (대기열 통과 시)
    if (canPurchase && token) {
        res = http.post(
            `${BASE_URL}/api/purchase`,
            JSON.stringify({
                productId: productId,
                quantity: 1,
                token: token,
            }),
            { headers: headers }
        );
        check(res, { '구매 성공': (r) => r.status === 200 });
    }

    sleep(1);
}

export function handleSummary(data) {
    return {
        stdout: textSummary(data, { indent: ' ', enableColors: true }),
        'k6-summary.json': JSON.stringify(data),
    };
}
