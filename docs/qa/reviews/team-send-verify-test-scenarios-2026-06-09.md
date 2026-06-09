# [위임 — 테스트 시나리오 사전 작성 + 검증 대기] team-send 검증 자동화 회귀 테스트

최종 갱신: 2026-06-09 by 정민

## 모드
- 분석 모드 (코드 변경 없음, 사전 시나리오 카탈로그)
- 발신자: 제임스 (CTO)
- 우선순위: 낮음 (본업 PR 리뷰·주간 dead code/CVE 스캔 우선, 사이 짬에 작성)
- 작업 repo: `/Users/vuno/Project/claude` (별도 인프라 repo)
- 본격 검증: 마크 구현 PR open 후 11개 시나리오 PASS/FAIL 매트릭스 작성 단계 진입

## 본 카탈로그의 위치

네이선 ADR 작성 + 마크 사전 조사·구현 흐름에서 **정민의 사전 산출물**. 마크 PR open 후 본 카탈로그를 acceptance criteria 로 사용해 자동 검증.

## 가정한 Hook 인터페이스 (마크 PR 까지 잠정)

마크 구현이 아직 확정되지 않았으므로 본 카탈로그는 다음 인터페이스를 **잠정 가정**한다. 실제 PR open 시 마크 구현과 일치시켜 본 카탈로그를 1회 보정한다.

- Hook 종류: **PostToolUse** (matcher: `Bash`).
- Hook 본문 흐름:
  1. tool_input 의 command 가 `team-send` 호출인지 jq 분기로 판별. 아니면 즉시 exit 0.
  2. team-send 의 stdout 마지막 `✅ <발신> → <수신> (pane N, KB)` 라인에서 pane index 추출.
  3. 1초 sleep 후 `tmux capture-pane -t <session>:0.<N> -p` 본문 끝 부분 capture.
  4. spinner 정규식 매칭 (예: `[✻✢✳✶✻] (Thinking|Envisioning|Crystallizing|Crunched|…)`) 확인.
  5. 미매칭 → `tmux send-keys -t <session>:0.<N> Enter` 보강 + 2초 sleep + 재 capture + 재매칭.
  6. 그래도 미매칭 → stderr 경고 + Hook exit 1 (Claude Code 가 사용자에게 표시).
- 예상 추가 지연: **최소 1초 (성공) ~ 최대 3초 (보강 후 실패)**.

## 시나리오 카탈로그 (총 11건)

각 시나리오는 (입력 / 예상 동작 / 검증 방법 / PASS 기준) 4-부 구조.

---

### A. 정상 케이스 (2건)

#### S1. spinner 있는 정상 발송 → Hook 무음 통과
- **입력**: 정민 페인에서 `team-send 마크 "[리뷰 결과] PR #X PASS"` 호출. 마크 페인 활성 + Claude prompt idle.
- **예상 동작**: team-send 자체 Enter 발동 정상 → 마크 페인 즉시 spinner 진입. Hook 이 1초 sleep 후 capture → spinner 매칭 → exit 0 (무음).
- **검증 방법**:
  1. team-send 호출 직후 마크 페인 `tmux capture-pane | tail -5` 에 spinner 표시 확인.
  2. Hook stdout/stderr 출력 없음 (silent).
  3. Hook 종료 코드 0.
- **PASS 기준**: 3개 모두 충족. Hook 추가 지연 ≤ 1.5초.

#### S2. team-send 외 Bash 호출 → Hook 즉시 스킵
- **입력**: 임의의 Bash 호출 (`ls`, `git status`, `grep ...`, `rg ...`).
- **예상 동작**: PostToolUse matcher 통과 후 jq 분기에서 `team-send` 명령 아님 판정 → 즉시 exit 0.
- **검증 방법**:
  1. 10개 비-team-send Bash 호출 실행 — `ls`, `git status`, `pwd`, `echo hi`, `cat /tmp/x`, `find . -name x`, `grep x file`, `cd /tmp`, `mkdir tmp`, `rm /tmp/x`.
  2. 각 호출의 Hook 응답 지연 측정 (`time` 또는 hook log).
  3. Hook stdout/stderr 출력 없음.
- **PASS 기준**: 10/10 silent + 추가 지연 ≤ 50ms (jq 분기만 수행).

---

### B. 회귀 케이스 (4건) — 본 자동화의 핵심 가치

#### S3. spinner 없는 발송 (Enter 미발동) → Hook 보강 성공
- **입력**: spinner 미발동 페인 상태를 의도적으로 만든다. 재현 후보:
  - (a) **3KB+ 메시지** — 큰 paste 의 Enter race condition (2026-05-28 사고 패턴, S5 와 중복이라 본 S3 는 작은 메시지로).
  - (b) **수신 페인이 idle 직후** (직전 spinner 종료 1초 이내).
  - (c) **mock 환경**: 사전에 `tmux send-keys -t <pane> "deadbeef"` 로 prompt 입력 부분에 dummy 텍스트 잔존시킨 후, 본 spinner 비유도 상태로 team-send 호출.
- **예상 동작**: team-send 의 자체 Enter 가 paste 처리 중 race 로 누락 → 1초 후 Hook capture 시 spinner 없음 → Hook 이 `tmux send-keys <pane> Enter` 보강 → 2초 후 spinner 진입 → 매칭 → exit 0.
- **검증 방법**:
  1. 의도 재현 후 team-send 호출.
  2. Hook log 에 "보강 Enter 발동" 표시.
  3. 최종 매칭 결과 spinner 확인.
  4. 종료 코드 0.
- **PASS 기준**: 보강 1회 후 spinner 진입 + Hook 종료 코드 0. **5회 반복 중 ≥4/5 성공** (race 자체가 비결정적이므로).

#### S4. Enter 보강해도 spinner 안 나옴 → stderr 경고 + exit 1
- **입력**: 수신 페인이 메뉴 화면 (예: `/usage`, `/help`, 모달 dialog) 잔존 상태. paste 자체는 도착하나 Enter 가 메뉴 인터랙션으로 처리되어 prompt 진입 안 됨.
- **예상 동작**: 1차 capture 시 spinner 없음 → Hook Enter 보강 → 메뉴가 Enter 를 흡수 → 2차 capture 시 여전히 spinner 없음 → stderr 경고 + exit 1.
- **검증 방법**:
  1. 수신 페인에서 사전에 `/usage` 또는 임의 메뉴 실행 후 메뉴 화면 잔존.
  2. team-send 호출.
  3. Hook stderr 에 명확한 경고 출력 — 메시지 도착·spinner 미발동·페인 idx + 진단 가이드 (`Esc 후 재발송 권장`).
  4. Hook 종료 코드 1.
- **PASS 기준**: stderr 경고 + exit 1. 경고 본문에 (a) 수신 페인 idx, (b) 메시지 미처리 사실, (c) 조치 가이드 3개 모두 포함.

#### S5. 큰 메시지 (3KB+) Enter 미발동 → Hook 보강 성공
- **입력**: `team-send 마크 -f /tmp/large-payload.md` 형식. 파일은 ≥3KB.
- **예상 동작**: team-send 자체 sleep 2초 + Enter 발동 → bracketed paste race 로 Enter 미발동 → Hook 보강 → spinner 진입.
- **검증 방법**:
  1. 3KB, 5KB, 10KB 3종 페이로드로 각 3회 = 9회 시도.
  2. team-send 자체 Enter 만으로 진입한 경우 vs Hook 보강으로 진입한 경우 분류.
  3. 두 경로 모두 최종 spinner 진입 + Hook exit 0.
- **PASS 기준**: 9/9 최종 진입 성공 + Hook exit 0. (boundary case: 자체 Enter 가 모두 정상이라 보강이 한 번도 안 일어나도 본 시나리오는 PASS — 보강 옵션이 동작함이 본 자동화의 fallback 가치.)

#### S6. /usage 같은 메뉴 화면 잔존 페인 — 마크 구현 결정 사항
- **입력**: S4 와 동일 (메뉴 잔존 상태).
- **분기점**: 마크 구현이 **(α) Hook 이 Esc 발사 후 재발송 시도** vs **(β) Hook 은 exit 1 + 사용자 안내만** 중 어느 쪽을 택하는지에 따라 본 시나리오 동작 다름.
  - α 라면: Hook 이 `tmux send-keys <pane> Escape` → 페인 메뉴 닫기 → 메시지 재 paste → Enter → spinner 진입.
  - β 라면: S4 와 동일 (exit 1 + 안내).
- **예상 동작**: 마크 PR open 시점에 결정. 본 카탈로그는 두 분기를 모두 기재.
- **검증 방법**:
  - α 검증: Esc 발사 → 메뉴 닫힘 capture 확인 → 재발송 → spinner 진입.
  - β 검증: S4 와 동일.
- **PASS 기준**: 마크 결정 후 보정. **정민 권장은 β** — Hook 이 Esc 같은 destructive 동작을 자동 발사하면 페인 사용자의 진행 중 작업을 깨뜨릴 위험 (예: 메뉴가 아닌 prompt 일 수도). β + 명확한 사용자 안내가 안전.
- **마크 결정 후속**: 본 시나리오를 별도 follow-up 으로 분리하고, β 채택 시 S6 = S4 의 중복으로 카탈로그에서 제거 (총 10건으로 축소).

---

### C. 엣지 케이스 (4건)

#### S7. 수신 페인 비활성 (Claude 셸 회귀) — team-send exit 4 → Hook skip
- **입력**: 수신 페인의 Claude 가 종료된 상태 (현재 셸 = bash/zsh/...).
- **예상 동작**: team-send 자체가 exit 4 로 거절 + stderr 출력 + 실제 send-keys 안 함 → Hook 이 PostToolUse 진입 시 team-send 자체 종료 코드 4 감지 → 즉시 exit 0 (Hook 가 본인 작업 안 함 — 보강할 페인 없음).
- **검증 방법**:
  1. 수신 페인에서 Claude `/exit` 또는 Ctrl+C 종료.
  2. team-send 호출.
  3. team-send stdout 에 ❌ + exit 4.
  4. Hook log 에 "team-send exit 4 — skip" 표시 + Hook exit 0.
  5. Hook 가 capture/Enter 보강 시도 흔적 없음 (불필요).
- **PASS 기준**: Hook skip + Hook exit 0. Hook 의 capture-pane / send-keys 호출 없음 (불필요한 부작용 방지).

#### S8. jq 미설치 환경 → Hook graceful degradation
- **입력**: Hook 본문이 jq 의존 시 (tool_input 분기), jq 가 PATH 에 없는 환경.
- **예상 동작**: Hook 이 jq command-not-found 감지 → stderr 경고 ("jq 미설치 — team-send 검증 skip") + exit 0 (Hook 자체는 무사 통과해 다음 PostToolUse 흐름 막지 않음).
- **검증 방법**:
  1. 임시로 PATH 에서 jq 제외 — `PATH=/tmp env -i bash` 같은 격리 환경.
  2. team-send 호출 시뮬레이션 (또는 직접 Hook 본문 실행).
  3. Hook stderr 에 명확한 경고.
  4. Hook 종료 코드 0 (degrade 모드).
- **PASS 기준**: 경고 + exit 0. 후속 Bash 호출 모두 정상 동작.
- **부록**: 마크 구현이 jq 의존이 아니면 (예: shell 내장 pattern matching) 본 시나리오 N/A. PR open 시 보정.

#### S9. tmux capture-pane 실패 (페인 사라짐) → Hook stderr 경고 + exit 1
- **입력**: team-send 호출 직후 ~ Hook capture 사이에 수신 페인이 종료되거나 세션이 사라짐. (실제 발생 빈도 낮으나 race 가능.)
- **예상 동작**: capture-pane 자체 종료 코드 ≠ 0 → Hook 이 본인 작업 불가 → stderr 경고 + exit 1.
- **검증 방법**:
  1. 인위적 재현: team-send 호출 직후 `tmux kill-pane -t <recipient>` 즉시 실행.
  2. Hook stderr 에 "capture-pane 실패 — 페인 사라짐 가능" 경고.
  3. Hook 종료 코드 1.
- **PASS 기준**: stderr 경고 + exit 1.
- **재현 난이도**: 중. timing 의존. 본 시나리오는 mock (Hook 본문에 `tmux capture-pane` 실패 시뮬레이션) 으로 대체 가능.

#### S10. spinner 정규식 false positive — Claude Code CLI 미래 버전 변경
- **입력**: 미래 Claude Code 가 spinner 문자 변경 (예: ✻ → ⠋ unicode braille). 현 정규식은 못 매칭.
- **예상 동작**: capture 시 spinner 매칭 실패 → Hook 이 정상 진입을 회귀로 오판 → 불필요 Enter 보강 → 페인에 중복 Enter 들어가 부작용 위험.
- **검증 방법**:
  1. Mock 환경에서 페인 capture 출력을 가짜 spinner 문자 (`⠋ Working...`) 로 교체.
  2. Hook 동작 관찰.
  3. **본 시나리오는 PR open 시점에서는 FAIL 예상** — 카탈로그의 "회귀 위험 식별" 가치.
- **PASS 기준**: 본 시나리오의 정상 PASS 는 spinner 정규식을 future-proof 하게 정의 (단일 문자 정규식 대신 `Crunched|Thinking|Envisioning|Crystallizing|...` 같은 영문 동사 매칭) 한 경우. 마크 구현 측 결정.
- **권장**: 정규식을 spinner 문자 (변경 가능) + 영문 동사 (안정) **OR 매칭** 으로 정의. 영문 동사도 i18n 시 변경 가능하므로 보수적으로는 spinner 정규식을 PATTERN ENV 로 외부 주입.

---

### D. 성능 케이스 (1건)

#### S11. Hook 응답 지연 측정
- **입력**: S1, S2, S3, S4 각 시나리오의 Hook 응답 지연을 100회 측정.
- **예상 동작**:
  - S1 (정상): 1초 sleep + capture + 정규식 = ≤1.5초.
  - S2 (skip): jq 분기만 = ≤50ms.
  - S3 (보강 성공): 1초 + capture + Enter + 2초 + capture = ≤3.5초.
  - S4 (실패): S3 와 동일 = ≤3.5초.
- **검증 방법**:
  1. 각 시나리오를 100회 반복.
  2. `time` 또는 hook log 에서 wall-clock 측정.
  3. p50/p95/p99 분포 작성.
- **PASS 기준**:
  - S1 p95 ≤ 1.5초.
  - S2 p95 ≤ 50ms.
  - S3, S4 p95 ≤ 3.5초.
- **카맥 작업과의 중복**: 카맥이 정량 perf 측정 + 회귀 게이트 담당이라면 본 시나리오의 100회 반복·통계 수집은 카맥에게 위임 권장. 정민 본 카탈로그는 회귀 임계 정의 + acceptance criteria 명시까지.

---

## 통합 PASS/FAIL 매트릭스 (마크 PR open 시 채움)

| ID | 카테고리 | 시나리오 | 예상 결과 | 실측 결과 | PASS/FAIL | 비고 |
|---|---|---|---|---|---|---|
| S1 | 정상 | spinner 정상 발송 | exit 0 silent | (마크 PR 후 측정) | — | — |
| S2 | 정상 | 비-team-send Bash | exit 0 silent | — | — | — |
| S3 | 회귀 | spinner 미발동 보강 | exit 0 보강 성공 ≥4/5 | — | — | — |
| S4 | 회귀 | 메뉴 잔존 — 보강 실패 | exit 1 경고 | — | — | — |
| S5 | 회귀 | 3KB+ Enter 미발동 | 9/9 진입 | — | — | — |
| S6 | 회귀 | 메뉴 화면 — α/β 분기 | 마크 결정 후 보정 | — | — | β 권장 |
| S7 | 엣지 | 수신 페인 비활성 | Hook skip + exit 0 | — | — | — |
| S8 | 엣지 | jq 미설치 | exit 0 degrade | — | — | jq 의존 시만 |
| S9 | 엣지 | capture-pane 실패 | exit 1 경고 | — | — | mock 대체 가능 |
| S10 | 엣지 | spinner 정규식 미래 회귀 | future-proof 검증 | — | — | 마크 결정 사항 |
| S11 | 성능 | Hook 지연 분포 | 임계 내 | — | — | 카맥 위임 권장 |

**머지 게이트**: S1~S5, S7, S8, S9 (8건) 모두 PASS 가 머지 조건. S6 (β 채택 시 제거), S10 (회귀 위험 식별만), S11 (카맥 위임) 은 후속.

---

## Acceptance Criteria 요약 (마크 PR 게이트)

1. S1, S2 — Hook 정상 silent 동작 + 다른 Bash 호출에 영향 없음.
2. S3 — 보강 메커니즘이 spinner 미발동을 실제로 회복 (≥4/5 시도 성공).
3. S4 — 보강 실패 시 명확한 stderr + 비-zero exit code.
4. S5 — 큰 메시지 (3KB+) 9/9 진입 성공.
5. S7 — team-send exit 4 시점에 Hook 부작용 없이 skip.
6. S9 — capture-pane 실패 시 Hook silent fail 가 아니라 명시적 경고.

위 6건 PASS = 머지 권장. S6/S8/S10/S11 은 PR 본문에 follow-up 명시.

---

## 후속 작업

- 마크 PR open 직후 본 카탈로그의 "마크 구현 결정 사항" (S6 α/β, S10 spinner pattern, S8 jq 의존) 을 PR 본문에 맞춰 1회 보정.
- 11건 시나리오 실제 실행 후 매트릭스 채움.
- 한 건이라도 FAIL 이면 PR 반려 + 마크 재작업.
- 본격 검증 결과는 별도 산출물 `docs/qa/reviews/team-send-verify-test-results-YYYY-MM-DD.md` 로 분리.

## 의존성·전제

- 본 카탈로그는 마크 구현이 PostToolUse Hook 기반임을 전제. 만약 마크가 다른 메커니즘 (예: team-send 자체에 검증 통합) 으로 결정하면 본 카탈로그의 Hook 인터페이스 가정은 폐기 → 일부 시나리오 (S2, S8) 재작성.
- 네이선 ADR 의 결정과도 정합 필요. 본 카탈로그 작성 시점에는 ADR 미수신 상태.

## 회신 형식

`team-send 제임스 -f /Users/vuno/Project/claude/docs/qa/reviews/team-send-verify-test-scenarios-2026-06-09.md`
