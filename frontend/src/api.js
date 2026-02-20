/**
 * API 클라이언트
 *
 * [면접 포인트]
 * Q: "API 에러 처리는 어떻게 하나요?"
 * A: 모든 응답을 ApiResponse 형식으로 통일하고,
 *    success 필드로 성공/실패를 판단합니다.
 *    프론트에서는 try-catch와 response.success 체크로 처리합니다.
 */

const API_BASE = (import.meta.env.VITE_API_URL || '') + '/api';

// 세션 ID 생성 (시연용 간소화)
const getSessionId = () => {
  let sessionId = sessionStorage.getItem('sessionId');
  if (!sessionId) {
    sessionId = 'session-' + Math.random().toString(36).substr(2, 9);
    sessionStorage.setItem('sessionId', sessionId);
  }
  return sessionId;
};

const fetchApi = async (url, options = {}) => {
  const response = await fetch(`${API_BASE}${url}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'X-Session-Id': getSessionId(),
      ...options.headers,
    },
  });

  const data = await response.json();

  if (!data.success) {
    throw new Error(data.message || '요청 처리 중 오류가 발생했습니다.');
  }

  return data.data;
};

// 상품 API
export const productApi = {
  getAll: () => fetchApi('/products'),
  getById: (id) => fetchApi(`/products/${id}`),
};

// 세일 API
export const saleApi = {
  getStatus: () => fetchApi('/sale/status'),
  start: () => fetchApi('/sale/start', { method: 'POST' }),
  end: () => fetchApi('/sale/end', { method: 'POST' }),
};

// 대기열 API
export const queueApi = {
  enter: (productId) => fetchApi('/queue/enter', {
    method: 'POST',
    body: JSON.stringify({ productId }),
  }),
  getStatus: (productId, token) =>
    fetchApi(`/queue/status?productId=${productId}&token=${token}`),
};

// 구매 API
export const purchaseApi = {
  purchase: (productId, quantity, token) => fetchApi('/purchase', {
    method: 'POST',
    body: JSON.stringify({ productId, quantity, token }),
  }),
};
