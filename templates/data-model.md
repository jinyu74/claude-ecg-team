<!-- 템플릿: docs/data-model.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Data Model
- 최종 갱신: 2026-05-12 by 네이선

## users
- id (uuid, pk)
- email (text, unique, not null)
- password_hash (text, not null)
- created_at (timestamptz, default now())

## sessions  (Redis, 비관계)
- key: sid:<uuid>
- value: { userId, createdAt, ua, ip }
- TTL: 14d
- 인덱스: byUser:<userId> (Set)

## 제약·결정
- PII 는 user 테이블에만. 다른 도메인은 user_id 참조.
- 비밀번호는 argon2id, 정책: docs/security.md
