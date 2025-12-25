import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const VUS = parseInt(__ENV.K6_VUS || '20', 10);
const DURATION = __ENV.K6_DURATION || '30s';
const VALUE_SIZE = parseInt(__ENV.K6_VALUE_SIZE || '128', 10);
const KEY_SPACE = parseInt(__ENV.K6_KEY_SPACE || '10000', 10);

const payload = JSON.stringify({ value: 'x'.repeat(VALUE_SIZE) });
const headers = { 'Content-Type': 'application/json' };
const putParams = { headers, tags: { name: 'PUT /kv/:key' } };
const getParams = { tags: { name: 'GET /kv/:key' } };
const mgetParams = { headers, tags: { name: 'POST /kv/mget' } };
const statsParams = { tags: { name: 'GET /stats' } };
const delParams = { tags: { name: 'DELETE /kv/:key' } };

export const options = {
  vus: VUS,
  duration: DURATION,
  summaryTrendStats: ['avg', 'p(50)', 'p(90)', 'p(99)'],
};

function key() {
  return `k6_${__VU}_${Math.floor(Math.random() * KEY_SPACE)}`;
}

export default function () {
  const k = key();

  const putRes = http.put(`${BASE_URL}/kv/${k}`, payload, putParams);
  check(putRes, { 'put status 200': (r) => r.status === 200 });

  const getRes = http.get(`${BASE_URL}/kv/${k}`, getParams);
  check(getRes, { 'get status 200/404': (r) => r.status === 200 || r.status === 404 });

  const mgetRes = http.post(`${BASE_URL}/kv/mget`, JSON.stringify({ keys: [k] }), mgetParams);
  check(mgetRes, { 'mget status 200': (r) => r.status === 200 });

  const statsRes = http.get(`${BASE_URL}/stats`, statsParams);
  check(statsRes, { 'stats status 200/503': (r) => r.status === 200 || r.status === 503 });

  const delRes = http.del(`${BASE_URL}/kv/${k}`, null, delParams);
  check(delRes, { 'delete status 200/503': (r) => r.status === 200 || r.status === 503 });

  sleep(0.1);
}
