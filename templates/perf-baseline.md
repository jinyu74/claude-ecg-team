<!-- 템플릿: docs/performance/baseline.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Performance Baseline
- 최종 갱신: 2026-05-14 by 카맥
- 환경: staging-2 / 측정 도구: k6 + pprof / N=10

## API
| 엔드포인트 | p50 | p95 | p99 | rps | 임계 (budget) |
|---|---|---|---|---|---|
| GET /api/search | 32ms | 88ms | 142ms | 420 | p95 100ms |
| POST /api/orders | 95ms | 178ms | 240ms | 180 | p95 200ms |

## Web (Core Web Vitals)
| 페이지 | LCP | INP | CLS | 비고 |
|---|---|---|---|---|
| 랜딩 | 2.1s | 140ms | 0.04 | mobile 3G |

## 측정 방법
- API: k6 (VUs 200, ramp 1min, sustain 10min)
- Web: Lighthouse CI on PR + 주간 RUM 샘플
