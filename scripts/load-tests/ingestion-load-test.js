import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const ingestionErrors  = new Counter('ingestion_errors');
const successRate      = new Rate('ingestion_success_rate');
const ingestionLatency = new Trend('ingestion_latency_ms', true);

export const options = {
  stages: [
    { duration: '1m',  target: 100  },
    { duration: '3m',  target: 500  },
    { duration: '1m',  target: 1000 },
    { duration: '30s', target: 0    },
  ],
  thresholds: {
    'http_req_duration{name:ingest}': ['p(95)<10', 'p(99)<50'],
    'ingestion_success_rate':         ['rate>0.999'],
    'http_req_failed':                ['rate<0.001'],
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://localhost:9090';

const SYMBOLS = ['BTC-USD', 'ETH-USD', 'AAPL', 'GOOGL', 'TSLA'];

function generateEvent() {
  return JSON.stringify({
    symbol:    SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)],
    price:     (Math.random() * 100000).toFixed(2),
    volume:    (Math.random() * 1000000).toFixed(2),
    timestamp: Date.now(),
    source:    'k6-load-test',
  });
}

export default function () {
  const start = Date.now();
  const res = http.post(
    `${BASE_URL}/v1/events`,
    generateEvent(),
    {
      headers: { 'Content-Type': 'application/json' },
      tags:    { name: 'ingest' },
    }
  );
  const dur = Date.now() - start;
  ingestionLatency.add(dur);

  const ok = check(res, {
    'status 200':          (r) => r.status === 200,
    'has event_id':        (r) => {
      try { return JSON.parse(r.body).event_id !== undefined; }
      catch (_) { return false; }
    },
  });

  successRate.add(ok);
  if (!ok) ingestionErrors.add(1);

  sleep(0.01);
}

export function handleSummary(data) {
  const m   = data.metrics;
  const p99 = m['http_req_duration{name:ingest}']?.values?.['p(99)'] ?? 999;
  const er  = (m['ingestion_success_rate']?.values?.rate ?? 0) * 100;

  console.log(`\n  p99=${p99.toFixed(2)}ms  success=${er.toFixed(3)}%`);
  console.log(`  SLO p99<10ms: ${p99 < 10 ? '✅' : '❌'}`);
  console.log(`  SLO >99.9%:   ${er > 99.9 ? '✅' : '❌'}\n`);

  return { 'results/load-test.json': JSON.stringify(data) };
}
