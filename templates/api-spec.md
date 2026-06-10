<!-- 템플릿: docs/api-spec.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# API Specification
- 최종 갱신: 2026-05-12 by 네이선
- 인증: 세션 쿠키 (ADR-014)

## POST /auth/login
- Request: { email: string, password: string }
- 200: { userId: string } + Set-Cookie: sid=...
- 401: { error: "INVALID_CREDENTIALS" }
- 429: rate limit (10/min/IP)

## POST /auth/logout
- 204
- 인증 필요

## DELETE /auth/sessions
- 204 (revokeAllFor)
- 인증 필요
