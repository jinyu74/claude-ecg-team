<!-- 템플릿: docs/design/a11y.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Accessibility Standards (WCAG 2.2 AA)
- 컬러 대비: 본문 4.5:1, 큰 글자 3:1
- 키보드만으로 모든 동작 가능
- focus 표시 윤곽 ≥ 3:1
- 색상에만 의존한 상태 표시 금지
- prefers-reduced-motion 존중

## 컴포넌트별 점검 결과
| 컴포넌트 | 키보드 | 스크린리더 | 대비 | reduced-motion | 비고 |
|---|---|---|---|---|---|
| SurfaceCard | ✅ | ✅ | ✅ | ✅ | |
| Button | ✅ | ✅ | ✅ | ✅ | |
| Modal | ✅ | ⚠️ | ✅ | ✅ | aria-modal 보강 필요 |
