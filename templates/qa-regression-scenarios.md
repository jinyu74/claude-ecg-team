<!-- 템플릿: docs/qa/regression-scenarios.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Regression Scenarios

- 최종 갱신: 2026-05-12 by 정민

## 인증 (ADR-014 이후)

| 시나리오               | 기대              | 자동화                             | 상태    |
| ---------------------- | ----------------- | ---------------------------------- | ------- |
| 만료 직후 요청         | 401               | e2e/auth.spec.ts:expired           | ✅      |
| 다중 디바이스 로그아웃 | 모든 세션 revoke  | integration/session.test:revokeAll | ⚠️ 누락 |
| Redis 단절             | 503 + Retry-After | integration/session.test:redisDown | ⚠️ 누락 |

## 결제

...
