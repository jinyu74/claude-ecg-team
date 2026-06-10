<!-- 템플릿: docs/analysis/ui-inventory.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# UI Inventory & Design Debt
- 최종 갱신: 2026-05-14 by 수영
- 코드 기준: commit a1b2c3d

## 컴포넌트 인벤토리
| 컴포넌트 | 경로 | 사용처 수 | 토큰 사용 | 상태 5종 | a11y | 비고 |
|---|---|---|---|---|---|---|
| Button | src/components/ui/Button.tsx | 42 | ✅ | ✅ | ✅ | |
| ButtonLegacy | src/components/old/Button.tsx | 8 | ⚠️ 하드코딩 | ⚠️ disabled 누락 | ⚠️ focus 약함 | **폐기 후보** |
| Card | src/components/ui/Card.tsx | 23 | ✅ | ✅ | ✅ | |
| Modal | src/components/ui/Modal.tsx | 11 | ✅ | ✅ | ⚠️ aria-modal 보강 필요 | |

## 디자인 부채
| 항목 | 영향 | 완화 비용 | 비고 |
|---|---|---|---|
| ButtonLegacy 8 사용처 | 중 | 1d | 마크에게 마이그 위임 후보 |
| 토큰 외 하드코딩 색상 17건 | 저 | 0.5d | grep 결과 |
| Modal aria-modal 누락 | 중 | 0.2d | a11y 회귀 |

## a11y 회귀 (월간)
- Modal: aria-modal 누락 (2026-05-14 확인)
- 기타 컴포넌트: 통과
