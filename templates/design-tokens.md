<!-- 템플릿: docs/design/tokens.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Design Tokens
- 최종 갱신: 2026-05-12 by 수영
- 토큰 정의 파일: src/styles/tokens.css

## 색상 (oklch)
| 토큰 | Light | Dark | 용도 |
|---|---|---|---|
| --color-surface | 98% 0 0 | 14% 0 0 | 페이지/카드 배경 |
| --color-text    | 18% 0 0 | 96% 0 0 | 본문 텍스트 |
| --color-accent  | 68% 0.21 250 | 동일 | CTA, 강조 |

## 타이포
- --text-base, --text-hero (clamp 사용)
- 폰트: Inter (본문), Suit (한글)
- 최대 2 패밀리

## 스페이싱
- 4px 베이스 그리드: --space-1 ~ --space-12

## 모션
- 기본 duration: --duration-fast 150ms / --duration-normal 300ms
- easing: --ease-out-expo
- prefers-reduced-motion 시 duration 0
