<!-- 템플릿: docs/performance/observability.md 생성용. 값은 예시 — 프로젝트에 맞게 대체한다. -->
# Observability
- 최종 갱신: 2026-05-14 by 카맥

## 메트릭
- RED: rate / errors / duration (모든 엔드포인트)
- USE: utilization / saturation / errors (호스트·DB·Redis)

## 대시보드
- API latency: grafana.example/d/api-latency
- DB: grafana.example/d/postgres

## 알람
| 알람 | 임계 | 채널 |
|---|---|---|
| p95 latency 5분 초과 | budget × 1.5 | #oncall |
| 에러율 5분 평균 | > 1% | #oncall |
