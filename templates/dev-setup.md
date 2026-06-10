<!-- 템플릿: docs/dev/setup.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Development Setup
- 최종 갱신: 2026-05-12 by 마크

## 요구 사항
- Node 20+, pnpm 9+, Docker, Redis 7+

## 1. 클론 & 의존성
pnpm install

## 2. 환경 변수
cp .env.example .env  # 값은 1Password/팀 비밀 저장소

## 3. 인프라 기동
docker compose up -d redis postgres

## 4. 마이그레이션
pnpm db:migrate

## 5. 실행
pnpm dev

## 테스트
pnpm test           # 단위 + 통합
pnpm test:e2e       # Playwright
