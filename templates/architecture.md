<!-- 템플릿: docs/architecture.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Architecture Overview
- 최종 갱신: 2026-05-12 by 네이선

## 컨텍스트
- 시스템 목적, 주요 사용자, 외부 시스템.

## 컴포넌트 (C4 Level 2)
- backend/api        — REST/GraphQL 게이트웨이
- backend/auth       — 인증 (ADR-014 기준 세션)
- backend/payment    — 결제
- backend/worker     — 비동기 작업
- infra/redis        — 세션·캐시
- infra/postgres     — 도메인 데이터

## 데이터 흐름
1. 사용자 → API → auth 미들웨어 → 도메인 핸들러 → DB
2. 비동기 이벤트 → worker → 외부 시스템

## 비기능 요구
- 가용성 99.9%, p95 API < 200ms

## 관련 ADR
- ADR-001 ~ ADR-014 (docs/adr/index.md 참조)
