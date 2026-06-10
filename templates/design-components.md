<!-- 템플릿: docs/design/components.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Component Catalog
- 최종 갱신: 2026-05-12 by 수영

## SurfaceCard
- 경로: src/components/ui/SurfaceCard.tsx
- Props: { title: string, body: string, href: string }
- 상태: default / hover / focus-visible / active / disabled
- 모션: hover 시 translateY(-2px)
- a11y: aria-label 필수, focus-visible outline 2px

## Button
- 경로: src/components/ui/Button.tsx
- Variant: primary / ghost / destructive
- 상태: 5 종 모두 디자인됨
- 키보드: Space/Enter 활성화
