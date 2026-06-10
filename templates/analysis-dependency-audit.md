<!-- 템플릿: docs/analysis/dependency-audit.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Dependency Audit
- 최종 갱신: 2026-05-14 by 수진
- 도구: npm audit + osv-scanner + 사내 grep

## 외부 의존성 현황
| 패키지 | 버전 | 최신 | 라이선스 | CVE | 사내 사용처 | 상태 |
|---|---|---|---|---|---|---|
| stripe | 7.2.0 | 14.5.0 | MIT | CVE-2025-XXXX (Medium) | payment/* | ⚠️ 업그레이드 권장 |
| redis | 4.6.0 | 4.7.0 | MIT | — | auth, cache | ✅ |
| pg | 8.11 | 8.12 | MIT | — | repo/* | ✅ |

## 월간 CVE 스캔 (2026-05)
- stripe@7.2.0 — Medium (정민에게 audit 등록 요청)
- 그 외 신규 CVE 없음.

## 후속
- stripe 업그레이드 — 네이선 ADR 후 마크 작업 (TECG-203).
