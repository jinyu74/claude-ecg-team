---
name: team-send-verify
description: team-send 호출 후 수신자 페인 활성 상태를 자동 검증하는 PostToolUse Hook 의 동작 원리·디버그·비활성화 가이드. team-send 사고 (Enter 미발동, spinner 미확인) 발생 시 또는 hook 발동 결과 진단이 필요할 때 참조.
---

# team-send-verify Hook 가이드

## 1. 본 hook 의 목적

`team-send <대상>` 호출 후 다음 사고를 자동 차단·복구한다:

- Enter 미발동 — bracketed paste race condition 으로 메시지가 수신자 input prompt 에 잔존
- spinner 미확인 — 발신자 Claude 가 자가 인식 한계로 active 상태 오판 (`✻ Crunched for Ns` 가 완료 메시지인데 active 로 잘못 분류 등)

본 hook 가 매 team-send 호출 직후 deterministic 으로 수신자 페인을 검증·보강한다.

## 2. 발동 조건

PostToolUse hook (matcher: `Bash`). 다음 모두 충족 시 본격 진입:

1. `tool_name == "Bash"`
2. `tool_input.command` 가 `team-send ` 로 시작 (직접 호출 / 경로 포함 / `; team-send` 체인 / `&& team-send` 체인 매칭)
3. `tool_response.stdout` 에 `✅ <발신> → <수신> (pane N, ...)` 성공 라인 포함

위 외 호출 (다른 Bash 명령, team-send 실패) 은 즉시 exit 0 으로 skip.

## 3. 활성 판정 패턴 (AND 매칭)

CTO 결정 (2026-06-09 §14.2). 두 조건 모두 충족 시만 active:

```bash
PATTERN_TOKENS='\([0-9]+s · [↑↓]'
PATTERN_VERBS='(Thinking|Envisioning|Crystallizing|Brewing|Billowing|Warping|Philosophising|Synthesizing)'
```

- `PATTERN_TOKENS` — 처리 중 토큰 카운터 footer `(Ns · ↑/↓ N tokens · esc to interrupt)`
- `PATTERN_VERBS` — 현재 활성 동사 (Claude Code UI 의 진행 중 표시)

**Crunched 는 의도적으로 제외**. `Crunched for Ns` 는 완료 후 메시지 — false positive 위험.

## 4. 동작 흐름

```
team-send 호출 (Bash 도구)
   ↓
[PostToolUse Hook 진입]
   ↓
jq 가용성 확인 → 미설치 시 stderr 안내 + exit 0
   ↓
tool_name / command / stdout 분기 → 비대상이면 exit 0
   ↓
stdout 의 `pane N` 파싱 → SESSION:0.N 타깃 결정
   ↓
sleep 2초 (카맥 임계 정합) → capture-pane → AND 매칭
   ↓
   ├── 매칭 성공: exit 0 (정상)
   ├── capture 실패: stderr + exit 2 (페인 사라짐 가능)
   └── 매칭 실패: tmux send-keys Enter 보강 + sleep 1 + 재확인
          ↓
          ├── 매칭 성공: exit 0 (복구)
          └── 매칭 실패: stderr 진단 가이드 + exit 2
```

## 5. Exit code 의미

| Code | 의미 | 발신자 Claude 영향 |
|---|---|---|
| 0 | 정상 (active 확인 / 비대상 / jq 없음) | 응답 정상 진행 |
| 2 | 보강 실패 — stderr 진단 가이드 노출 | 발신자 진단 절차 진입 (수동 capture/Esc) |

본 hook 는 **destructive 동작 (Esc 자동 발사 등) 을 절대 수행하지 않는다** (정민 권장 S6 β + CTO 결재 §14.5). 보강 실패 시 사용자에게 정보만 제공.

## 6. 로그

`/tmp/team-send-verify.log` 에 발동 이력 기록.

```
[2026-06-09 15:20:42] OK pane=4 active (1차)
[2026-06-09 15:21:15] WARN pane=0 no active — Enter 보강 송신
[2026-06-09 15:21:16] RECOVERED pane=0 Enter 보강 성공
[2026-06-09 15:30:01] FAIL pane=2 Enter 보강 후도 미활성
```

진단 명령:

```bash
tail -20 /tmp/team-send-verify.log
```

## 7. 비활성화 절차 (긴급 / 디버그)

### 7.1 임시 비활성화 (재시작 없이 즉시)

```bash
jq 'del(.hooks.PostToolUse[]?.hooks[]? | select(.command | endswith("team-send-verify.sh")))' \
    ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json
```

file watcher 가 즉시 픽업 → 다음 Bash 호출부터 hook 미진입.

### 7.2 영구 비활성화

`~/.claude/settings.json` 의 `hooks.PostToolUse` 배열에서 `team-send-verify.sh` 엔트리 직접 제거 후 저장.

### 7.3 재활성화

```bash
bash /Users/vuno/Project/claude/setup-team.sh --hook-only
```

또는 setup-team.sh 전체 재실행 — idempotent jq merge 로 안전 재등록.

## 8. 자주 발생하는 오작동·진단

### 8.1 정상 발송인데 exit 2 가 자주 발생

- 원인 후보:
  1. Claude Code UI spinner 패턴 변경 (PATTERN_VERBS 미매칭)
  2. sleep 2 가 짧음 (수신자 페인이 느리게 응답)
- 진단: `tail /tmp/team-send-verify.log` 에서 `WARN ... no active` 빈도 확인
- 대응: `bin/team-send-verify.sh` 의 PATTERN_VERBS 보강 또는 SLEEP_INITIAL 증가 (3초)

### 8.2 jq 미설치 안내가 매 호출 표시

- 원인: 본 환경에 jq 없음
- 대응: `brew install jq` (macOS) / `apt install jq` (Ubuntu)
- 안내가 거슬리면 §7.1 으로 hook 임시 비활성

### 8.3 다른 PostToolUse hook 가 추가됐는데 보존 안 됨

- 원인: jq smart merge 실패 가능성 — setup-team.sh 의 merge 패턴 점검
- 진단: `~/.claude/settings.json.bak.*` 백업으로 복원 비교
- 대응: 본 ADR §3.4 의 smart merge 패턴 (group_by + unique_by) 사용 확인

## 9. 의존성

- **jq** — stdin JSON 파싱. 미설치 시 graceful exit 0 + stderr 안내. macOS 기본 포함, Linux 는 `apt install jq` 또는 `yum install jq`.
- **tmux** — capture-pane / send-keys. setup-team.sh 사전 요구사항.
- **bash 4+** — 본 스크립트 표준.

## 10. 관련 문서

- ADR: `docs/decisions/2026-06-09-team-send-verify-hook.md`
- 회귀 시나리오 카탈로그: `docs/qa/reviews/team-send-verify-test-scenarios-2026-06-09.md`
- workflow: `roles/_team-workflow.md` §8.2.1 / §8.2.2 / §8.4.1 / §8.4.2

## 11. 의도적 비포함

본 hook 는 다음을 **의도적으로 수행하지 않는다**:

- **Esc 자동 발사** — 페인에 메뉴가 아닌 prompt 가 있을 수도 있어 사용자 작업 파괴 위험 (S6 β)
- **메시지 재발송** — 중복 paste 위험. 발신자 Claude 의 명시적 재호출에 위임
- **수신자 측 검증** — 본 hook 는 발신자 측 PostToolUse 만. 수신자 측은 별도 sprint

## 12. 사용자가 본 가이드를 부를 만한 상황

- "team-send-verify hook 가 자주 exit 2 내요"
- "hook 발동 로그 어디서 봐요"
- "임시로 hook 비활성화하고 싶어요"
- "새 PostToolUse hook 추가했는데 본 hook 와 충돌해요"
- "Claude Code UI 가 바뀐 후로 검증이 false positive 내요"
