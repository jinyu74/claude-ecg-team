<!-- 템플릿: docs/analysis/audit/<topic>.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Audit: 결제 모듈 보안 — 2026-05-14

- audit 대상: backend/payment/*
- 코드 기준: commit a1b2c3d
- 도구: security-scan + 수동 검토
- audit 자: 정민

## 종합
- 결론: **HIGH 2 / MED 1 / LOW 1**. 제임스 사인오프 요청.

## 발견 사항
### HIGH-1: PCI 로그 마스킹 누락
- 위치: backend/payment/payment_service.ts:88
- 위협: stripe 응답이 그대로 로그에 노출 (카드 마지막 4자리 포함 가능)
- 제안: 응답 직렬화 시 PII 필드 마스킹 함수 적용
- 후속: TECG-201 자동 생성 권장

### HIGH-2: 결제 멱등 키 미점검
- 위치: backend/payment/order_controller.ts:42
- 위협: 동일 주문 중복 결제 가능 (네트워크 재시도 시)
- 제안: Idempotency-Key 헤더 필수 + Redis 기반 저장

### MED-1: refund 권한 검증 누락
- 위치: backend/payment/refund_controller.ts:30
- 제안: admin role 필수 미들웨어 추가

### LOW-1: 변수명 `tmp` → `pending_charge`

## 후속 조치
- HIGH 2건 → 제임스에게 즉시 보고. Jira Sub-task 생성.
- 회귀 시나리오 신규 등록 → docs/qa/regression-scenarios.md
- 본 audit 은 docs/analysis/index.md 에 등재.
