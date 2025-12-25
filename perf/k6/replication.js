import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const VUS = parseInt(__ENV.K6_VUS || '10', 10);
const DURATION = __ENV.K6_DURATION || '30s';

export const options = {
  vus: VUS,
  duration: DURATION,
  summaryTrendStats: ['avg', 'p(50)', 'p(90)', 'p(99)'],
  discardResponseBodies: true,
};

const infoParams = { tags: { name: 'GET /replication/info' } };
const snapshotParams = { tags: { name: 'GET /replication/snapshot' } };
const aofParams = { tags: { name: 'GET /replication/aof' } };

export default function () {
  const infoRes = http.get(`${BASE_URL}/replication/info`, infoParams);
  check(infoRes, { 'info status 200/503': (r) => r.status === 200 || r.status === 503 });

  const snapshotRes = http.get(`${BASE_URL}/replication/snapshot`, snapshotParams);
  check(snapshotRes, { 'snapshot status 200/503': (r) => r.status === 200 || r.status === 503 });

  const aofRes = http.get(`${BASE_URL}/replication/aof?since=0&max_bytes=65536`, aofParams);
  check(aofRes, { 'aof status 200/204/503': (r) => [200, 204, 503].includes(r.status) });

  sleep(0.1);
}
