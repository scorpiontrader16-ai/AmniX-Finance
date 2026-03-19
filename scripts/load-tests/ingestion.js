// scripts/load-tests/ingestion.js
// k6 Load Testing — Ingestion + Processing Services
//
// داخل cluster:
//   INGESTION_URL  = http://ingestion-stable.platform.svc.cluster.local:8080
//   PROCESSING_URL = http://processing-stable.platform.svc.cluster.local:50051
//
// محلياً عبر port-forward:
//   INGESTION_URL  = http://localhost:8080
//   PROCESSING_URL = http://localhost:50051
//
// تشغيل:
//   k6 run --env SCENARIO=smoke  --env INGESTION_URL=... ingestion.js
//   k6 run --env SCENARIO=load   --env INGESTION_URL=... ingestion.js
//   k6 run --env SCENARIO=stress --env INGESTION_URL=... ingestion.js

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ── Custom Metrics ──────────────────────────────────────────────────────
const errorRate         = new Rate('error_rate');
const ingestionLatency  = new Trend('ingestion_latency',  true);
const processingLatency = new Trend('processing_latency', true);
const eventsAccepted    = new Counter('events_accepted');
const eventsRejected    = new Counter('events_rejected');

// ── Config ──────────────────────────────────────────────────────────────
const INGESTION_URL  = __ENV.INGESTION_URL
  || 'http://ingestion-stable.platform.svc.cluster.local:8080';
const PROCESSING_URL = __ENV.PROCESSING_URL
  || 'http://processing-stable.platform.svc.cluster.local:50051';
const SCENARIO       = __ENV.SCENARIO || 'smoke';

// ── Scenarios ───────────────────────────────────────────────────────────
const SCENARIOS = {
  smoke: {
    executor:     'constant-vus',
    vus:          2,
    duration:     '30s',
    gracefulStop: '10s',
  },
  load: {
    executor:         'ramping-vus',
    startVUs:         0,
    stages: [
      { duration: '1m', target: 10  },
      { duration: '3m', target: 50  },
      { duration: '1m', target: 100 },
      { duration: '2m', target: 100 },
      { duration: '1m', target: 0   },
    ],
    gracefulRampDown: '30s',
  },
  stress: {
    executor:         'ramping-vus',
    startVUs:         0,
    stages: [
      { duration: '2m', target: 100 },
      { duration: '5m', target: 200 },
      { duration: '2m', target: 300 },
      { duration: '5m', target: 300 },
      { duration: '2m', target: 0   },
    ],
    gracefulRampDown: '30s',
  },
};

// ── Validation ──────────────────────────────────────────────────────────
if (!SCENARIOS[SCENARIO]) {
  throw new Error(`Unknown SCENARIO="${SCENARIO}". Valid: smoke | load | stress`);
}

// ── Options ─────────────────────────────────────────────────────────────
// تصحيح: http_req_duration مرة واحدة فقط — تكرار الـ key يُلغي القيمة الأولى في JS
export const options = {
  scenarios: {
    [SCENARIO]: SCENARIOS[SCENARIO],
  },
  thresholds: {
    'http_req_failed':      ['rate<0.01'],
    'http_req_duration':    ['p(95)<500', 'p(99)<1000'],
    'error_rate':           ['rate<0.01'],
    'ingestion_latency':    ['p(95)<400'],
    'processing_latency':   ['p(95)<600'],
  },
};

// ── Test Data ───────────────────────────────────────────────────────────
const EVENT_TYPES = [
  'user.clicked',
  'trade.executed',
  'sensor.reading',
  'order.created',
  'payment.processed',
];

function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function generateEvent() {
  return JSON.stringify({
    event_id:   `load-test-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    event_type: randomItem(EVENT_TYPES),
    source:     'k6-load-test',
    payload: {
      value:     Math.random() * 1000,
      timestamp: Date.now(),
    },
  });
}

const BASE_HEADERS = {
  'Content-Type':     'application/json',
  'X-Event-Source':   'k6-load-test',
  'X-Schema-Version': '1.0.0',
  'X-Tenant-ID':      'load-test-tenant',
};

// ── Main ────────────────────────────────────────────────────────────────
export default function () {
  const payload = generateEvent();

  // ── Ingestion ───────────────────────────────────────────────────
  group('ingestion-service', () => {
    const start = Date.now();
    const res = http.post(
      `${INGESTION_URL}/v1/events`,
      payload,
      {
        headers: { ...BASE_HEADERS, 'X-Event-Type': randomItem(EVENT_TYPES) },
        tags:    { service: 'ingestion' },
      }
    );

    ingestionLatency.add(Date.now() - start);

    const ok = check(res, {
      'ingestion: status 200': (r) => r.status === 200,
      'ingestion: has event_id': (r) => {
        try { return JSON.parse(r.body).event_id !== undefined; }
        catch { return false; }
      },
      'ingestion: accepted true': (r) => {
        try { return JSON.parse(r.body).accepted === true; }
        catch { return false; }
      },
      'ingestion: latency < 500ms': (r) => r.timings.duration < 500,
    });

    errorRate.add(!ok);
    res.status === 200 ? eventsAccepted.add(1) : eventsRejected.add(1);
  });

  sleep(0.1);

  // ── Processing ──────────────────────────────────────────────────
  group('processing-service', () => {
    const start = Date.now();
    const res = http.post(
      `${PROCESSING_URL}/v1/process`,
      payload,
      {
        headers: { ...BASE_HEADERS },
        tags:    { service: 'processing' },
      }
    );

    processingLatency.add(Date.now() - start);

    const ok = check(res, {
      'processing: status 200':      (r) => r.status === 200,
      'processing: latency < 600ms': (r) => r.timings.duration < 600,
    });

    errorRate.add(!ok);
  });

  sleep(0.1);
}

// ── Setup ───────────────────────────────────────────────────────────────
export function setup() {
  const ingRes  = http.get(`${INGESTION_URL}/healthz`);
  const procRes = http.get(`${PROCESSING_URL}/healthz`);

  if (ingRes.status !== 200) {
    throw new Error(
      `Ingestion not ready — HTTP ${ingRes.status} @ ${INGESTION_URL}/healthz`
    );
  }
  if (procRes.status !== 200) {
    throw new Error(
      `Processing not ready — HTTP ${procRes.status} @ ${PROCESSING_URL}/healthz`
    );
  }

  console.log(`✓ ingestion  @ ${INGESTION_URL}`);
  console.log(`✓ processing @ ${PROCESSING_URL}`);
  console.log(`→ scenario: ${SCENARIO}`);

  return { ingestionUrl: INGESTION_URL, processingUrl: PROCESSING_URL };
}

// ── Teardown ────────────────────────────────────────────────────────────
export function teardown(data) {
  console.log(`✓ done | ingestion: ${data.ingestionUrl} | processing: ${data.processingUrl}`);
}
