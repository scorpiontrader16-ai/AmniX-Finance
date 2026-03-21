// scripts/load-tests/ingestion.js — Fixed
// FIX 1: INGESTION_URL بدل BASE_URL
// FIX 2: default() يتوقف لو setup() رجع skipped=true
// FIX 3: Processing بيستخدم HTTP port 9093 مش gRPC 50051

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import exec from 'k6/execution';

// ── Custom Metrics ──────────────────────────────────────────────────────
const errorRate         = new Rate('error_rate');
const ingestionLatency  = new Trend('ingestion_latency',  true);
const processingLatency = new Trend('processing_latency', true);
const eventsAccepted    = new Counter('events_accepted');
const eventsRejected    = new Counter('events_rejected');

// ── Config ──────────────────────────────────────────────────────────────
// FIX: INGESTION_URL و PROCESSING_URL (بدل BASE_URL)
const INGESTION_URL  = __ENV.INGESTION_URL
  || 'http://ingestion-stable.platform.svc.cluster.local:9091';
const PROCESSING_URL = __ENV.PROCESSING_URL
  || 'http://processing-stable.platform.svc.cluster.local:9093';
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

if (!SCENARIOS[SCENARIO]) {
  throw new Error(`Unknown SCENARIO="${SCENARIO}". Valid: smoke | load | stress`);
}

export const options = {
  scenarios: {
    [SCENARIO]: SCENARIOS[SCENARIO],
  },
  thresholds: {
    'http_req_failed':    ['rate<0.01'],
    'http_req_duration':  ['p(95)<500', 'p(99)<1000'],
    'error_rate':         ['rate<0.01'],
    'ingestion_latency':  ['p(95)<400'],
    'processing_latency': ['p(95)<600'],
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
export default function (data) {
  // FIX: لو setup() رجع skipped=true → abort فوراً مش نكمل
  // ده بيمنع إن الـ requests تشتغل على cluster URL مش موجودة
  if (data && data.skipped) {
    exec.test.abort('No real cluster available — set INGESTION_URL env var');
    return;
  }

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
      'ingestion: status 200':      (r) => r.status === 200,
      'ingestion: has event_id':    (r) => {
        try { return JSON.parse(r.body).event_id !== undefined; }
        catch { return false; }
      },
      'ingestion: accepted true':   (r) => {
        try { return JSON.parse(r.body).accepted === true; }
        catch { return false; }
      },
      'ingestion: latency < 500ms': (r) => r.timings.duration < 500,
    });

    errorRate.add(!ok);
    res.status === 200 ? eventsAccepted.add(1) : eventsRejected.add(1);
  });

  sleep(0.1);

  // ── Processing — HTTP healthz على port 9093 ─────────────────────
  group('processing-service', () => {
    const start = Date.now();
    const res = http.get(
      `${PROCESSING_URL}/healthz`,
      { tags: { service: 'processing' } }
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
  const isClusterUrl = INGESTION_URL.includes('svc.cluster.local');

  // FIX: لو cluster URL (مش موجودة في CI) → skip بـ flag صريح
  // الـ default() function هتشوف الـ flag وتعمل abort
  if (isClusterUrl) {
    console.log('⚠️  Cluster URL detected — skipping test (no K8s cluster in CI)');
    console.log('   To run against real cluster: set INGESTION_URL and PROCESSING_URL');
    return { skipped: true };
  }

  const ingRes  = http.get(`${INGESTION_URL}/healthz`);
  const procRes = http.get(`${PROCESSING_URL}/healthz`);

  if (ingRes.status !== 200) {
    throw new Error(`Ingestion not ready — HTTP ${ingRes.status} @ ${INGESTION_URL}/healthz`);
  }
  if (procRes.status !== 200) {
    throw new Error(`Processing not ready — HTTP ${procRes.status} @ ${PROCESSING_URL}/healthz`);
  }

  console.log(`✓ ingestion  @ ${INGESTION_URL}`);
  console.log(`✓ processing @ ${PROCESSING_URL}`);
  console.log(`→ scenario: ${SCENARIO}`);

  return { skipped: false, ingestionUrl: INGESTION_URL, processingUrl: PROCESSING_URL };
}

// ── Teardown ────────────────────────────────────────────────────────────
export function teardown(data) {
  if (!data || data.skipped) {
    console.log('ℹ️  Test skipped — no real cluster available');
    return;
  }
  console.log(`✓ done | ingestion: ${data.ingestionUrl} | processing: ${data.processingUrl}`);
}
