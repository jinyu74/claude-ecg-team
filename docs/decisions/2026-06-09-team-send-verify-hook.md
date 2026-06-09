# ADR: team-send 검증 자동화 — PostToolUse Hook + 보조 스킬 패키지

- 상태: **Accepted** (CTO 검수 통과 2026-06-09 15:02)
- 일자: 2026-06-09
- 의사결정자: 제임스 (CTO), 네이선 (Architect)
- 작성: 네이선 (위임자 제임스 2026-06-09 14:51)
- 우선순위: UNIV v1.0.0.0 과 병렬 즉시 진입 (CEO 결재 2026-06-09)
- Jira: 없음 (본 인프라 repo PR/commit 으로만 진행 — CEO 결재)

## 갱신 이력

| 일자·시각 | 갱신자 | 내용 |
|---|---|---|
| 2026-06-09 14:51~15:00 | 네이선 | 초안 작성 (commit `ad82d63`) |
| 2026-06-09 15:02 | CTO 검수 통과 | §14 4종 결정 답변 수신 |
| 2026-06-09 15:05 | 네이선 | §5 의사 코드 AND 매칭 패턴 반영 + §5.1 정규식 근거 재작성 (Crunched 제외 + `esc to interrupt` 제외) |

---

## 1. 결함 정의

### 1.1 사고 패턴

`team-send <대상> -f <파일>` 호출 시 다음 흐름:

1. 발신자 페인의 Claude → Bash 도구로 `team-send` 실행
2. `team-send` 가 수신자 페인에 `tmux load-buffer + paste-buffer + send-keys Enter` 발동
3. 정상 흐름: 수신자 Claude 가 즉시 처리 → spinner (`✻ Thinking…` 등) 표시
4. 사고 흐름: bracketed paste race condition / paste 안정화 대기 (`sleep $SLEEP_SEC`) 부족 / 수신자 idle 직후 timing 정렬 실패 → Enter 미발동 → 메시지가 input prompt 에 잔존하고 수신자 Claude 는 처리 시작 안 함

발신자 측에서 보면:
- `team-send` 자체는 `✅ <발신> → <수신> (pane N, NB)` 출력 + exit 0 종료.
- 발신자 Claude 는 종료 코드만 보고 "전달 성공" 으로 판정 → 응답 종료.
- 수신자 Claude 는 메시지 잔존, idle 상태로 다음 사이클 진입 대기.

결과: **메시지 미처리 사고** — 사용자 수동 개입 발생.

### 1.2 발견 시점

| 일자 | 사고 | 메시지 크기 | 발신자 |
|---|---|---|---|
| 2026-05-28 12:52 | TECG-455 위임 Enter 미발동, CEO 직접 발동 | 3450B | (자율 모드) |
| 2026-06-09 (다회) | 4명 분담 위임 Enter 미발동, CEO 직접 발동 | 다양 | 제임스 |

### 1.3 기존 완화책의 한계

`roles/_team-workflow.md §8.2.1` 은 발신자 의무로 다음 검증 4단계를 강제:

1. Bash 종료 코드 0 확인
2. 비0 시 stderr 진단
3. `tmux capture-pane` 으로 수신자 메시지 잔존 확인
4. footer 영역 spinner 표시 확인 — 없으면 `tmux send-keys Enter` 보강

문제:
- (4) 의 spinner 확인은 **발신자 Claude 의 자가 인식**에 의존. LLM 환각으로 "footer 가 `esc to interrupt` 보이니 active" 로 잘못 판정 (`feedback_team_send_spinner_verify.md` 학습 기록 참조).
- 매 team-send 마다 4단계 수동 검증 = 비용 + 누락 위험.

→ **자동화 필요**. PostToolUse Hook 으로 발신자 Claude 응답 종료 전 강제 검증.

---

## 2. 설계 목표

| 항목 | 목표 |
|---|---|
| 1. spinner 미확인 누락 차단 | 99%+ (검증 자동화 보완) |
| 2. 응답 지연 추가 | < 2초 (sleep 2 재확인 + 보강 Enter) |
| 3. 새 팀 셋업 자동 배포 | `setup-team.sh` 1회 실행으로 Hook + 스킬 동시 활성 |
| 4. 기존 사용자 설정 보호 | 다른 Hook 와 공존 (jq smart merge — §4-2-c) |
| 5. 실패 시 안전성 | Hook 실패가 본 Bash 실행 자체를 차단하지 않음 (warning only) |
| 6. 디버그 가능성 | 발동 로그 (`/tmp/team-send-verify.log`) 추적 가능 |

비목표:
- team-send 자체의 race condition 해소 (paste-buffer race) — 별도 sprint
- 수신자 측 Hook (현 범위는 발신자 측 PostToolUse 만)

---

## 3. 확정 불가 4종 — 실험 결과

claude-code-guide 사전 조사에서 본 환경 검증이 필요했던 4종.

### 3.1 stdin JSON 스키마 — **확정**

**검증 출처**:
- `~/.claude/plugins/cache/everything-claude-code/everything-claude-code/2.0.0-rc.1/.cursor/hooks/adapter.js:28-46`
- `~/.claude/plugins/cache/everything-claude-code/everything-claude-code/2.0.0-rc.1/tests/integration/hooks.test.js:308-328, 350-364`

**PostToolUse Bash 호출 시 stdin 스키마**:

```json
{
  "session_id": "uuid-string",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/Users/vuno/Project/...",
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "team-send 제임스 -f /tmp/report.md",
    "description": "Send report to CTO"
  },
  "tool_response": {
    "stdout": "✅ 네이선 → 제임스 (pane 0, 5249B)\n",
    "stderr": "",
    "interrupted": false,
    "isError": false
  }
}
```

**참고**: 일부 문서·예제는 `tool_response` 대신 `tool_output` 키를 사용. 본 ADR 구현은 두 키 모두 폴백 처리.

**검증 방법 (구현 시 마크가 Step 0 으로 수행)**: 최소 hook 스크립트 `cat > /tmp/hook-stdin.json` 으로 1회 dump → 스키마 실측.

### 3.2 스킬 자동 로딩 메커니즘 — **확정**

**검증 출처**:
- `~/.claude/plugins/cache/everything-claude-code/everything-claude-code/2.0.0-rc.1/skills/golang-testing/SKILL.md` (frontmatter 형식 실측)
- Claude Code 세션 시작 시 `<system-reminder>` 에 사용 가능한 스킬 description 자동 surfacing

**결론**:

| 메커니즘 | 자동 발동 | 비고 |
|---|---|---|
| 스킬 frontmatter `description` 매칭 | △ 부분 자동 | Claude 가 description 과 user 요청 매칭 시 자가 판단으로 invoke |
| `/skill-name` 명시 호출 | ○ 확정적 | 사용자/Claude 의 명시 invoke |
| `triggers` / `keywords` 키워드 트리거 | ✗ **미지원** | 본 환경 확인 — 매 Bash 호출마다 자동 발동 안 됨 |

**시사점**: **매 `team-send` 호출에 자동 검증 발동은 스킬로 불가**. Hook 만이 deterministic 자동 발동 가능. 스킬은 보조 가이드 (사용자가 `/team-send-verify` 명시 호출 시 검증 절차 안내) 역할.

### 3.3 스킬 + Hook 복합 발동 — **확정**

**구조**: 스킬과 Hook 는 독립 레이어.

```
사용자 요청
   ↓
[Skill 자동 surface] (description 매칭) — 선택적
   ↓
Claude 응답 생성 + Bash 도구 호출
   ↓
[PreToolUse Hook] — deterministic, 명령 modify/block 가능
   ↓
Bash 실행 (`team-send ...`)
   ↓
[PostToolUse Hook] — deterministic, 검증·보강 진입
   ↓
Claude 응답 종료
```

**결론**: 스킬 → Bash → Hook 순차 흐름 자체는 작동. 단 스킬은 발동을 **trigger** 하지 않음. 스킬은 Claude 가 *어떻게 응답할지* 의 가이드만 제공. 실제 매 호출 자동 검증은 **Hook 단독** 책임.

### 3.4 jq merge 안전성 — **실측 확정**

**검증**: 본 ADR §3.4 실험 (`/tmp/exp4-*.json` 4건 시나리오).

| 시나리오 | naive `.[0] * .[1]` | smart `group_by + unique_by` |
|---|---|---|
| 1. PostToolUse 미존재 (신규 추가) | ✅ | ✅ |
| 2. 동일 입력 재실행 (idempotent) | ✅ | ✅ |
| 3. 동일 matcher 다른 command 공존 | ❌ **덮어쓰기** | ✅ append + 보존 |
| 4. 동일 (matcher, command) 재실행 | ❌ 중복 추가 | ✅ unique |

**결정**: **smart merge 패턴 채택**.

```bash
jq -s '
  .[0] as $base | .[1] as $new |
  $base
  | .hooks.PostToolUse =
      ([($base.hooks.PostToolUse // [])[], ($new.hooks.PostToolUse // [])[]]
        | group_by(.matcher)
        | map({
            matcher: .[0].matcher,
            hooks: ([.[].hooks[]] | unique_by(.command))
          })
      )
' base.json new-hook.json
```

**한계**: `unique_by(.command)` 은 command 문자열 일치 기준. 인자 미세 변경 (예: 옵션 추가) 시 별개 hook 로 취급 — 의도된 동작.

---

## 4. 파일 구조

claude-code-guide 권장 구조를 본 repo 컨벤션에 맞춰 확정·수정.

### 4.1 본 repo 추가 파일

```
/Users/vuno/Project/claude/
├── bin/
│   ├── team-send                       (기존)
│   ├── team-status                     (기존)
│   └── team-send-verify.sh             (신규 — PostToolUse Hook 본체)
├── skills/                             (신규 디렉토리)
│   └── team-send-verify/
│       └── SKILL.md                    (신규 — 보조 가이드)
├── setup-team.sh                       (수정 — Hook 등록 + skills 배포)
└── docs/
    └── decisions/
        └── 2026-06-09-team-send-verify-hook.md  (본 ADR)
```

### 4.2 Hook 등록 위치 — **사용자 전역 `~/.claude/settings.json`**

| 옵션 | 장점 | 단점 |
|---|---|---|
| (a) 본 repo 로컬 `.claude/settings.json` | 격리, repo 한정 | 페인별 cwd 다양 — 매 페인에 활성 보장 안 됨 |
| (b) **사용자 전역 `~/.claude/settings.json`** | 모든 페인 자동 활성 | 다른 사용자 Hook 와 공존 필요 — §3.4 smart merge 로 해결 |
| (c) 본 repo `settings.local.json` | 개발자별 옵트인 | 자동 배포 안 됨 |

**채택: (b)**. `setup-team.sh` 가 `~/.claude/settings.json` 에 jq smart merge 로 hook 등록.

### 4.3 스킬 배포 위치 — **사용자 전역 `~/.claude/skills/`**

`setup-team.sh` 가 본 repo `skills/team-send-verify/` 를 `~/.claude/skills/team-send-verify/` 로 복사 (idempotent rsync 권장).

---

## 5. 검증 스크립트 의사 코드

`/Users/vuno/Project/claude/bin/team-send-verify.sh` (PostToolUse Bash hook 본체):

```bash
#!/usr/bin/env bash
# PostToolUse Bash hook — team-send 호출 후 수신자 페인 spinner 검증 + Enter 보강
# 본 hook 은 stdin 으로 PostToolUse JSON 페이로드를 수신 (§3.1 스키마 확정).

set -uo pipefail
LOG=/tmp/team-send-verify.log

# ── 1. stdin JSON 파싱 — Bash 도구가 아니면 즉시 exit 0 ────────────────────
PAYLOAD=$(cat)
TOOL_NAME=$(jq -r '.tool_name // ""' <<<"$PAYLOAD")
[ "$TOOL_NAME" = "Bash" ] || exit 0

# ── 2. team-send 명령이 아니면 즉시 exit 0 ────────────────────────────────
COMMAND=$(jq -r '.tool_input.command // ""' <<<"$PAYLOAD")
case "$COMMAND" in
    *team-send*) ;;
    *) exit 0 ;;
esac

# ── 3. team-send 자체가 실패했으면 검증 skip — 본인 응답에서 진단 진입 ─────
EXIT_CODE=$(jq -r '.tool_response.isError // false' <<<"$PAYLOAD")
STDOUT=$(jq -r '.tool_response.stdout // .tool_output.output // ""' <<<"$PAYLOAD")
case "$STDOUT" in
    *"✅"*"→"*"(pane"*) ;;  # 성공 출력 패턴 — 계속 진행
    *) exit 0 ;;            # 성공 패턴 없으면 fail 상태 — 본인 응답에서 진단
esac

# ── 4. 발신자·수신자·pane 인덱스 파싱 ─────────────────────────────────────
#     출력 예: "✅ 네이선 → 제임스 (pane 0, 5249B)"
TARGET_PANE=$(printf '%s' "$STDOUT" | grep -oE 'pane [0-9]+' | head -1 | awk '{print $2}')
[ -n "$TARGET_PANE" ] || exit 0

SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo team)
TARGET="${SESSION}:0.${TARGET_PANE}"

# ── 5. AND 매칭 활성 판정 함수 — false positive 방지 (CTO 결정 2026-06-09) ─
#     PATTERN_TOKENS: 처리 중 토큰 카운터 (`(Ns · ↑/↓ N tokens`)
#     PATTERN_VERBS:  현재 활성 동사 (Crunched 제외 — 완료 메시지 패턴)
#     **AND 매칭**: 두 정규식 모두 충족 시만 active. 단일 조건은 false positive.
PATTERN_TOKENS='\([0-9]+s · [↑↓]'
PATTERN_VERBS='(Thinking|Envisioning|Crystallizing|Brewing|Billowing|Warping|Philosophising|Synthesizing)'

verify_active() {
    local capture
    capture=$(tmux capture-pane -t "$TARGET" -p 2>/dev/null | tail -5)
    grep -qE "$PATTERN_TOKENS" <<<"$capture" && \
    grep -qE "$PATTERN_VERBS" <<<"$capture"
}

# ── 6. 2 초 sleep 후 수신자 페인 활성 점검 ─────────────────────────────────
#     2초 = 카맥 임계 1M context TTFT p95 (2.5s) 의 안전 마진 내. recall 우선.
sleep 2
if verify_active; then
    echo "[verify] OK pane=${TARGET_PANE} active" >>"$LOG"
    exit 0
fi

# ── 7. 미발동 — 보강 Enter 송신 ───────────────────────────────────────────
echo "[verify] WARN pane=${TARGET_PANE} no active — sending Enter" >>"$LOG"
tmux send-keys -t "$TARGET" Enter
sleep 1
if verify_active; then
    echo "[verify] RECOVERED pane=${TARGET_PANE}" >>"$LOG"
    exit 0
fi
CAPTURE2=$(tmux capture-pane -t "$TARGET" -p 2>/dev/null | tail -5)

# ── 8. 복구 실패 — exit 2 로 본인 Claude 에 stderr 전달 ───────────────────
echo "[verify] FAIL pane=${TARGET_PANE} Enter 보강 후에도 active 아님" >>"$LOG"
cat >&2 <<EOF
[team-send-verify] 수신자 pane=${TARGET_PANE} 에 메시지 잔존 가능.
capture-pane 결과:
${CAPTURE2}

수동 진단: tmux capture-pane -t ${TARGET} -p | tail -10
수동 보강: tmux send-keys -t ${TARGET} Enter
EOF
exit 2
```

**Exit code 의미**:

| Code | 의미 | 본인 Claude 영향 |
|---|---|---|
| 0 | 정상 (spinner 확인 또는 본 hook 비대상) | 응답 정상 진행 |
| 2 | 보강 실패 — stderr 전달 | 본인 Claude 에 stderr 노출, 응답에서 진단 진입 |
| 그 외 | 비예상 오류 | warning 표시 (응답 차단 안 함) |

### 5.1 정규식 근거 — AND 매칭 채택 (CTO 결정 2026-06-09 15:02)

본인 (CTO) SSOT memory + 마크 사전 조사 §5 + 정민 카탈로그 S10 future-proof 권장 종합 결론.

#### PATTERN_TOKENS — 활성 토큰 카운터

```
\([0-9]+s · [↑↓]
```

처리 중인 동안 footer 영역에 표시되는 elapsed time + token counter 패턴 (예: `(12s · ↑ 1.4k tokens`). 활성 처리만 본 패턴을 표시 — 완료·idle 상태에서는 사라짐.

#### PATTERN_VERBS — 활성 동사 (Crunched 제외)

```
(Thinking|Envisioning|Crystallizing|Brewing|Billowing|Warping|Philosophising|Synthesizing)
```

Claude Code UI 의 활성 처리 동사 8 종. **`Crunched` 의도적 제외** — `Crunched for Ns · ↑ N tokens` 는 **완료** 메시지로 `PATTERN_TOKENS` 에 매칭되므로, `PATTERN_VERBS` 가 단독으로 차단해야 active false positive 방지.

#### AND 매칭의 정당성

| 시나리오 | TOKENS | VERBS | AND 판정 |
|---|---|---|---|
| 활성 처리 중 (`Thinking… (12s · ↑ 1.4k tokens`) | ✓ | ✓ | **active** ✓ |
| 완료 직후 (`Crunched for 9s · ↑ 1.4k tokens`) | ✓ | ✗ | **inactive** ✓ |
| idle prompt (footer 없음) | ✗ | ✗ | **inactive** ✓ |
| `esc to interrupt` 단독 (이전 출력 잔존) | ✗ | ✗ | **inactive** ✓ (false positive 차단) |

**`esc to interrupt` 제외 사유**: footer 영역에 잔존하는 경우 false positive 위험 — `feedback_team_send_spinner_verify.md` 학습 교훈 (2026-06-09 CEO 직접 발동 사고).

#### sleep 2 의 정당성

- 카맥 임계: 1M context TTFT p95 = 2.5s.
- 2초 sleep 후 capture 시 활성 패턴 미표시면 Enter 미발동 확정 (마진 0.5s 내).
- recall 우선 — false negative (active 인데 inactive 판정) 줄이는 방향.

#### 향후 future-proof

- Claude Code 가 새 동사 추가 시 `PATTERN_VERBS` 갱신 — 정민 카탈로그 S10 권장.
- `PATTERN_TOKENS` 는 footer 영역 UI 변경 영향. 변경 감지 시 본 ADR 후속 ADR 로 갱신.

---

## 6. Hook 등록 위치 + 새 팀 자동 배포

### 6.1 설계 결정

| 결정 | 채택 |
|---|---|
| 등록 위치 | 사용자 전역 `~/.claude/settings.json` (§4.2 (b)) |
| 자동 배포 | `setup-team.sh` 가 jq smart merge 로 등록 |
| 스킬 배포 | `setup-team.sh` 가 `~/.claude/skills/team-send-verify/` 로 rsync |
| 본 repo bin/ 노출 | `setup-team.sh` 가 페인 start_claude_in_pane 단계에서 PATH 노출 (기존 동작) |

### 6.2 `~/.claude/settings.json` 등록 후 형태

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "rtk hook claude"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "/Users/vuno/Project/claude/bin/team-send-verify.sh"}
        ]
      }
    ]
  }
}
```

기존 PreToolUse `rtk hook claude` 와 무관하게 PostToolUse 라인에 추가됨. §3.4 smart merge 로 다른 PostToolUse hook 존재 시 unique_by(.command) 로 보존·추가.

---

## 7. `setup-team.sh` 갱신 방향

### 7.1 추가 단계 (스크립트 시작부, tmux 세션 생성 전)

```bash
# ── (신규) team-send-verify Hook 등록 — idempotent jq smart merge ─────────
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_CMD="$SCRIPT_DIR/bin/team-send-verify.sh"

if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
fi

# 신규 hook 패치 생성
PATCH=$(cat <<EOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$HOOK_CMD"}
        ]
      }
    ]
  }
}
EOF
)

# smart merge — §3.4 검증된 패턴
MERGED=$(jq -s --argjson patch "$PATCH" '
  .[0] as $base |
  $base
  | .hooks //= {}
  | .hooks.PostToolUse =
      ([(.hooks.PostToolUse // [])[], ($patch.hooks.PostToolUse // [])[]]
        | group_by(.matcher)
        | map({
            matcher: .[0].matcher,
            hooks: ([.[].hooks[]] | unique_by(.command))
          })
      )
' "$SETTINGS_FILE" /dev/null)

# 원자적 쓰기 — temp + mv 로 부분 쓰기 사고 방지
TMP="$(mktemp)"
printf '%s\n' "$MERGED" > "$TMP"
mv "$TMP" "$SETTINGS_FILE"
echo -e "${GREEN}✓${NC} ~/.claude/settings.json — team-send-verify hook 등록"

# ── (신규) 스킬 배포 — rsync idempotent ────────────────────────────────────
mkdir -p "$HOME/.claude/skills"
rsync -a --delete "$SCRIPT_DIR/skills/team-send-verify/" \
    "$HOME/.claude/skills/team-send-verify/"
echo -e "${GREEN}✓${NC} ~/.claude/skills/team-send-verify/ 배포"
```

### 7.2 idempotent 보장

- jq smart merge — 동일 (matcher, command) 재실행 시 unique_by 로 중복 차단 (§3.4 실험).
- rsync `-a --delete` — 본 repo skills/ 디렉토리가 SSOT. 사용자 임의 수정은 다음 setup-team.sh 실행 시 본 repo 버전으로 복원.
- temp + mv — 부분 쓰기 사고 방지.

### 7.3 의존성 추가

`setup-team.sh` 의존성에 `jq` 추가 (README 갱신).

---

## 8. 롤백 절차

### 8.1 Hook 발동 자체 실패 시 (안전 기본값)

본 hook 는 **exit 2 외에는 본인 Bash 호출을 차단하지 않음**:
- exit 0: 정상 완료
- exit 2: warning + stderr 노출, 단 Bash 결과 자체는 본인 Claude 에 전달됨
- 비예상 exit (스크립트 오류 등): warning 만, 차단 없음 (Claude Code 기본 동작)

→ Hook 가 망가져도 team-send 자체는 계속 작동.

### 8.2 응답 진입 실패 사고 발생 시

수신자 페인이 idle 상태로 계속 잔존 시:

1. **본인 Claude 에서 진단**: `tmux capture-pane -t <session>:0.<pane> -p | tail -10`
2. **수동 보강**: `tmux send-keys -t <session>:0.<pane> Enter`
3. **Hook 로그 확인**: `tail -20 /tmp/team-send-verify.log` 에서 WARN/FAIL 패턴 확인

### 8.3 Hook 자체 비활성화 (긴급 시)

```bash
# 임시 비활성화 — settings.json 백업 후 PostToolUse 라인 제거
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq 'del(.hooks.PostToolUse[]?.hooks[]? | select(.command | endswith("team-send-verify.sh")))' \
    ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json
```

### 8.4 완전 롤백

1. `git revert <commit>` (본 repo) — `setup-team.sh` 변경 되돌리기
2. `~/.claude/settings.json` 백업 복원
3. `rm -rf ~/.claude/skills/team-send-verify/`
4. `rm /tmp/team-send-verify.log`

---

## 9. `roles/_team-workflow.md` §8.2.1 갱신 초안

기존 §8.2.1 (4단계 수동 검증 의무) 는 유지하되, 본 hook 도입 후 다음 문구 추가:

```markdown
### 8.2.1 송신 후 검증 (의무 — 모든 크기 메시지 공통)

`team-send` 호출 후 **반드시 다음 4단계 확인**한 뒤에야 "전달 완료" 보고:

1. Bash 도구의 **종료 코드 = 0** (셸 출력 마지막 줄 `✅ <발신> → <수신> (pane N)`)
2. 비0 종료 시 stderr 메시지로 원인 식별 (exit 3 = 페인 없음, exit 4 = 비활성)
3. **수신자 페인 capture 으로 메시지 전달 확인** ... (기존)
4. **Enter 발동 확인** ... (기존)

**자동화 보완 (2026-06-09 추가)**:
- 본 repo `bin/team-send-verify.sh` PostToolUse Hook 가 위 3·4 단계를 자동 수행.
- Hook 가 spinner 미확인 시 자동 Enter 보강 + exit 2 stderr 노출.
- 발신자 Claude 는 Hook stderr 가 노출되면 즉시 진단 절차 진입 (기존 4단계 매뉴얼과 동일).
- **Hook 도입 후에도 본 §8.2.1 4단계 의무는 유효** — Hook 는 보완책이지 면제책 아님.
  Hook 실패 시 (jq 오류, tmux 비가용, 스크립트 손상) 매뉴얼 검증 fallback.

**디버그 로그**: `tail -20 /tmp/team-send-verify.log` 으로 본 hook 발동 이력 확인.
```

---

## 10. 후속 흐름

1. **본 ADR 승인** — 제임스 (CTO) 사인오프.
2. **마크 (Developer) 위임** — `bin/team-send-verify.sh` 구현 + `setup-team.sh` 갱신 + `skills/team-send-verify/SKILL.md` 작성. Step 0 으로 §3.1 stdin 스키마 실측 dump.
3. **정민 (QA) 테스트** — 다음 시나리오 회귀 시나리오:
   - (T1) 정상 spinner 확인 → exit 0
   - (T2) Enter 미발동 → 보강 후 spinner 확인 → exit 0
   - (T3) Enter 보강 후에도 미발동 → exit 2 + stderr
   - (T4) team-send 자체 실패 → hook 즉시 exit 0 (검증 skip)
   - (T5) Bash 명령이 team-send 아님 → hook 즉시 exit 0
3. **카맥 (Performance) 측정** — 추가 응답 지연 < 2초 목표 검증 (sleep 2 + capture + 정규식 매칭 부담).
4. **`_team-workflow.md` §8.2.1 본 ADR §9 초안 반영** — 별도 commit (메타 작업 push destination 표준 §메타 작업 push destination 표준 준수).

---

## 11. 대안 (거절 사유 명시)

### (A) 스킬 단독 — Hook 없이

- 매 team-send 마다 자동 발동 불가 (§3.2). 발신자 Claude 의 자가 인식 의존 → 현 문제 잔존.
- **거절**.

### (B) Hook 단독 — 스킬 없이

- 자동화는 충분. 단 hook 가 망가졌을 때의 매뉴얼 절차 문서 부재 → 디버그 어려움.
- 본 ADR 의 hybrid (Hook 주, 스킬 보조) 가 우위.
- **거절**.

### (C) team-send 자체에 검증 내장 (PostToolUse 미사용)

- team-send 셸 스크립트 끝에 sleep 2 + capture + Enter 보강 추가.
- 장점: 의존성 단순화 (Hook + settings.json 등록 불필요).
- 단점:
  - 매 team-send 호출이 +2초 직렬 지연 (사용자 직접 호출 시에도).
  - 발신자 Claude 가 sleep 2 결과를 무시할 수 없게 됨 — 의식적 fast-skip 옵션 불가.
  - claude-code-guide 가 권장한 deterministic Hook 분리 패턴과 어긋남.
- **거절** — 단 향후 hook 가 사용자 경험에 부담 시 재고 후보.

### (D) 수신자 측 Hook (PreToolUse 또는 SessionStart)

- 수신자 Claude 의 input prompt 메시지 잔존 감지 + 자동 Enter.
- 구현 복잡: Claude 가 자기 input prompt 상태를 외부에서 모니터링하기 어려움.
- 발신자 측 Hook 가 시간적으로 먼저 발동하므로 발신자 측 해결이 자연.
- **거절**.

---

## 12. 결과 요약

- **+ ** 매 team-send 호출 자동 검증 → spinner 미확인 누락 99% 차단.
- **+ ** 본 repo `setup-team.sh` 1회 실행으로 새 팀 셋업 시 자동 활성.
- **+ ** 다른 Hook (rtk hook 등) 공존 — jq smart merge 로 보호.
- **+ ** 본 hook 실패 시 team-send 자체는 계속 작동 (안전 기본값).
- **− ** 응답 지연 +2초 (capture-pane race window).
- **− ** jq 의존성 추가 (대부분 환경에 기설치, brew 1줄).
- **− ** `~/.claude/settings.json` 사용자 전역 수정 — 다른 도구 충돌 시 진단 부담 (smart merge 로 완화).

---

## 13. 관련 자료

- 본 사고 학습 기록:
  - `feedback_team_send_enter_verify.md` (2026-05-28)
  - `feedback_team_send_spinner_verify.md` (2026-06-09)
  - `feedback_team_send_bash_invoke.md` (2026-06-05)
- 본 repo:
  - `bin/team-send` (검증 대상 스크립트)
  - `setup-team.sh` (갱신 대상)
  - `roles/_team-workflow.md` §8.2.1 (갱신 초안 §9)
- 외부:
  - 본 Hook 스키마 출처: `~/.claude/plugins/cache/everything-claude-code/2.0.0-rc.1/.cursor/hooks/adapter.js`
  - claude-code-guide 사전 조사 결과 (제임스 위임 메시지 인용)

---

## 14. 의사결정 결과 (CTO 답변 2026-06-09 15:02)

| # | 항목 | 결과 |
|---|---|---|
| 1 | §4.2 Hook 등록 위치 (b) 사용자 전역 | **동의** |
| 2 | §5 sleep 2 + spinner 정규식 | **AND 매칭 채택** — `PATTERN_TOKENS` + `PATTERN_VERBS` (Crunched 제외) 반영 완료 (§5.1) |
| 3 | §9 `_team-workflow.md` hybrid 정책 | **동의** — Hook 도입 후에도 매뉴얼 4단계 유지 |
| 4 | §10 후속 흐름 | **동의** — 마크 본격 구현 즉시 진입, Step 0 (stdin 스키마) 생략 (마크 사전 조사 §2.1 완료) |

### 후속 검증 (마크 PR open 단계)

- §3 실험은 본인 (네이선) 환경 진행 — 마크·정민·카맥 페인에서 동일 동작 검증 필요. 정민 회귀 단계에 흡수.
- §9 Hook exit 2 사용자 alert 실측 — 마크 PR open 직후 정민 회귀 S4 시나리오에 흡수.
- 마크 PR open 시 본인 (네이선) 이 ADR 정합성 재점검만 진입.
