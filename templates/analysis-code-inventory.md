<!-- 템플릿: docs/analysis/code-inventory.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Code Inventory
- 최종 갱신: 2026-05-14 by 수진
- 코드 기준: commit a1b2c3d

## 모듈별 인벤토리
| 모듈 | 경로 | 파일 수 | 핵심 기능 | 사용처 | 최근 30d 변경 | 커버리지 |
|---|---|---|---|---|---|---|
| auth | backend/auth/ | 14 | 세션·로그인·OAuth | api, worker | 6 | 88% |
| payment | backend/payment/ | 22 | Stripe 통합·정산 | api, cron | 12 | 71% |
| search | backend/search/ | 9 | 상품 검색 | api | 2 | 80% |

## 유사 구현 클러스터 (통합 후보)
- `redis.ts` / `cache.ts` / `kv.ts` — 3개 모듈에서 Redis 어댑터 중복 (네이선 ADR 후보)
- `validator.ts` 가 모듈마다 별도 — zod 통합 검토 후보
