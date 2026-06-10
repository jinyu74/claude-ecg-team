<!-- 템플릿: docs/performance/regression-perf.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Performance Regression Scenarios
- 최종 갱신: 2026-05-14 by 카맥

## API
| 시나리오 | 임계 | 자동화 위치 | 상태 |
|---|---|---|---|
| /api/search p95 | 100ms | k6/scripts/search.js (CI nightly) | ✅ |
| /api/orders p95 | 200ms | k6/scripts/orders.js (CI nightly) | ✅ |

## Web
| 시나리오 | 임계 | 자동화 위치 | 상태 |
|---|---|---|---|
| 랜딩 LCP | 2.5s | lighthouserc.json (per-PR) | ✅ |
