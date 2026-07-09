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
| 2026-06-09 15:05 | 네이선 | §5 AND 매칭 패턴 반영 + §5.1 정규식 근거 재작성 (마크 PR `5752947` 에 흡수) |
| 2026-06-09 15:32 | 카맥 Phase 2 측정 | AND 매칭 두 BUG 식별 — VERBS 열거 누락 + TOKENS 분 포맷 미지원 |
| 2026-06-09 15:34 | CTO 정정 | 단일 PATTERN_ACTIVE 채택 결정 — Hook 본체 즉시 반영 (마크 PR `5752947`) |
| 2026-06-09 16:00+ | 네이선 | ADR §5/§5.1 단일 패턴으로 사후 정합 — Hook 본체와 일치시킴 |
| 2026-07-09 | 카맥·네이선·정민 | **설계 전환**: verify.sh 로그 전용 강등 + team-send 에 positive delivery 루프 이관 (commit `b3b5873`) |

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
| 2. 응답 지연 추가 | ~~< 2초 (sleep 2 재확인 + 보강 Enter)~~ — 2026-07-09 §5.2 positive delivery 전환으로 blocking 제거. 지연 없음. |
| 3. 새 팀 셋업 자동 배포 | `setup-team.sh` 1회 실행으로 Hook + 스킬 동시 활성 |
| 4. 기존 사용자 설정 보호 | 다른 Hook 와 공존 (jq smart merge — §4-2-c) |
| 5. 실패 시 안전성 | Hook 실패가 본 Bash 실행 자체를 차단하지 않음 (warning only) |
| 6. 디버그 가능성 | 발동 로그 (`/tmp/team-send-verify.log`) 추적 가능 |

비목표:
- ~~team-send 자체의 race condition 해소 (paste-buffer race) — 별도 sprint~~ → **2026-07-09 달성**: team-send 내 positive delivery 루프로 해소 (§5.2)
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

## 5. 검증 스크립트 — 현행 동작 (2026-07-09 설계 전환)

### 5.1 verify.sh — 로그 전용 (blocking 제거)

**배경**: 구 PATTERN_ACTIVE blocking 방식은 1M context reasoning 중 footer 카운터가 미표시되어 오경보 43.5% 발생(2026-07-09 카맥 진단). 근본 원인은 "detector 신호"(footer 카운터)가 아닌 "transport"(paste + Enter) 레이어의 문제. detector 를 강화하는 대신 transport 자체에 delivery 확인을 내장하는 방향으로 전환(네이선 Q3 방향, 정민 6케이스 실측 통과).

`/Users/vuno/Project/claude/bin/team-send-verify.sh` (현행, line 72-77):

```bash
# ── 7. non-blocking 로그 전용 ─────────────────────────────────────────────
# delivery 확인은 team-send 내 positive delivery 루프로 이관 (2026-07-09).
# 구 PATTERN_ACTIVE blocking 검증·Enter 보강·exit 2 차단 제거.
# 본 hook 는 전송 이력 로깅만 수행하고 exit 0 으로 종료한다.
echo "[$TS] LOG pane=${TARGET_PANE} team-send 완료" >>"$LOG" 2>/dev/null || true
exit 0
```

**Exit code**:

| Code | 의미 |
|---|---|
| 0 | 항상 (로그 기록 후 종료 — blocking 없음) |

### 5.2 team-send — positive delivery 루프 (신규, 2026-07-09)

`/Users/vuno/Project/claude/bin/team-send` (line 181-209):

```bash
# ── positive delivery 확인 (Enter 발동 후 입력창 잔존 체크) ─────────
# 판정 신호 (❯ 이후 입력창 구간만 검사 — transcript 에코 제외):
#   (1) "Press up to edit queued" — 큐잉 성공 → OK
#   (2) "Pasted text"             — collapse placeholder 잔존(긴 메시지) → 미제출
#   (3) MSG_PROBE                 — 짧은 메시지 비-collapse 잔존 안전망
MSG_PROBE="$(printf '%s' "$PAYLOAD" | head -1 | cut -c1-25)"
_DELIVERED=1
for _i in 1 2 3; do
    sleep 0.7
    _CAP="$(tmux capture-pane -t "$TARGET" -p 2>/dev/null | tail -20)"
    # 큐잉 성공 신호 → 즉시 OK
    printf '%s' "$_CAP" | grep -qF "Press up to edit queued" && { _DELIVERED=1; break; }
    # ❯ 이후 구간(입력창)만 추출 — transcript 에코 방지 (마지막 ❯ 기준)
    _INPUT_AREA="$(printf '%s' "$_CAP" | awk '/❯/{buf=""; found=1} found{buf=buf$0 ORS} END{printf "%s", buf}')"
    # 잔존 검사 먼저 — 입력창에 잔존 있으면 확정 미제출 → 재발사
    if printf '%s' "$_INPUT_AREA" | grep -qF "Pasted text" || \
       { [ -n "$MSG_PROBE" ] && printf '%s' "$_INPUT_AREA" | grep -qF "$MSG_PROBE"; }; then
        tmux send-keys -t "$TARGET" Enter 2>/dev/null
        _DELIVERED=0
    else
        _DELIVERED=1; break  # 입력창 비어있음 = 제출 성공 (esc든 idle이든 무관)
    fi
done
# 3회 소진 후 잔존 신호 잔류 시 경고
[ "$_DELIVERED" -eq 0 ] && echo "⚠️ ${SENDER} → ${RECIPIENT_NAME} delivery 미확인 — 수동 확인 권장" >&2
```

**판정 근거**: 제출 성공이면 paste 가 transcript 로 이동해 입력창에서 사라짐 → 입력창 잔존 = 미제출 확정. 비어있으면 제출 성공 (reasoning 중이든 idle 이든 무관). 단, 실제 소실(턴 경계 레이스 1/1680)은 입력창이 비어있으므로 허용.

**오경보 측정**: 구 PATTERN_ACTIVE 방식 43.5% FAIL → 신 방식 0%(LOG 전용, 2026-07-09 실측).

### 5.3 구 §5.1 정규식 근거 — Deprecated (2026-07-09)

PATTERN_ACTIVE(`\(([0-9]+m )?[0-9]+s · [↑↓]`)는 verify.sh 에서 제거됨. 판정 책임이 team-send 의 입력창 잔존 grep 으로 이관됐으므로 본 패턴은 더 이상 운영되지 않는다. 이력 보존 목적으로 §5.1 원문은 git history 참조.

### 5.1 정규식 근거 — 단일 PATTERN_ACTIVE 채택 (CTO §14.2 정정 2026-06-09 15:34)

#### 결정 경로

| 일시 | 단계 | 결정 |
|---|---|---|
| 15:02 | CTO 1차 답변 | AND 매칭 (PATTERN_TOKENS + PATTERN_VERBS) — Crunched 제외 |
| 15:32 | 카맥 Phase 2 측정 발견 | AND 매칭 두 BUG 식별 (아래) |
| 15:34 | CTO 2차 정정 | **단일 PATTERN_ACTIVE 채택** — 두 BUG 동시 해소 |

#### AND 매칭의 두 BUG (Deprecated)

1. **PATTERN_VERBS 열거 누락**: Claude Code UI 가 새 동사 (`Combobulating` / `Transfiguring` / `Composing`) 를 지속 추가. 8 종 열거는 구조적 회귀 위험.
2. **PATTERN_TOKENS 분 포맷 미지원**: `\([0-9]+s · [↑↓]` 는 `(15s · ↑ ...)` 매칭. 하지만 1분 이상 처리 시 `(1m 6s · ↑ ...)` 형식 → **미매칭 BUG** (false negative).

#### PATTERN_ACTIVE — 단일 패턴

```
\(([0-9]+m )?[0-9]+s · [↑↓]
```

- 활성 토큰 카운터 footer 의 **괄호 + (옵션) 분 + 초 + 화살표** 매칭.
- 예: `(15s · ↑ 234 tokens)`, `(1m 6s · ↓ 3.4k tokens)` — 모두 매칭.
- Crunched 같은 완료 메시지 (`Crunched for 9s · ↑ 1.4k tokens`) 는 **괄호 부재** 로 자동 차단.
- ERE 호환: `(...)` 은 단순 그룹 (캡처 결과 미사용). 카맥 원본 PCRE `(?:...)` 비포착 그룹 → grep -E ERE 호환 형식으로 마크 보강.

#### 단일 패턴의 정당성

| 시나리오 | PATTERN_ACTIVE 판정 |
|---|---|
| 활성 처리 중 (`Thinking (15s · ↑ 234 tokens)`) | **active** ✓ |
| 활성 처리 중 (`Combobulating (15s · ↑ ...)` — 신규 동사) | **active** ✓ (동사 무관) |
| 활성 처리 1분 초과 (`Thinking (1m 6s · ↓ 3.4k tokens)`) | **active** ✓ (분 포맷 지원) |
| 완료 직후 (`Crunched for 9s · ↑ 1.4k tokens`) | **inactive** ✓ (괄호 부재) |
| idle prompt (footer 없음) | **inactive** ✓ |
| `esc to interrupt` 단독 (이전 출력 잔존) | **inactive** ✓ (괄호+화살표 부재) |

#### sleep 2.5 의 정당성

- 카맥 Phase 2 측정: 1M context TTFT p95 ≈ 2.5s.
- 2.5초 sleep 후 capture 시 활성 패턴 미표시면 Enter 미발동 확정 (회귀 빈도 < 5%).
- 카맥 측정 결과 사후 갱신 — 본 ADR §5.1 표 동기화 필수.

#### 향후 future-proof

- **footer 영역 UI 변경 감지 시 본 ADR 후속 ADR 로 갱신**. 단일 패턴이므로 변경 반경 작음 (괄호·시간·화살표 부분만).
- 동사 열거는 본 패턴 무관 — 본 부분의 회귀 위험 해소.
- 정민 카탈로그 S10 future-proof 우려도 본 단일 패턴으로 해소 (시나리오 보정 필요 — 정민 PR open 후 흡수).

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

본 hook 는 **항상 exit 0** (로그 전용 — 2026-07-09 이후):
- exit 0: 로그 기록 후 정상 종료 (유일한 exit code)
- 어떠한 경우에도 발신자 Bash 호출을 차단하지 않음
- Hook 자체가 손상되어도 team-send 는 계속 작동

> ~~구 동작 (2026-06-09~2026-07-08): exit 2 + stderr 노출 → 2026-07-09 positive delivery 전환으로 제거.~~

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

**자동화 보완 현행 (2026-07-09 갱신)**:
- `bin/team-send` 의 **positive delivery 루프** (§5.2) 가 3·4 단계를 대신 수행. Enter 발동 후 입력창 잔존 검사 + 필요 시 재발사(최대 3회). verify.sh Hook 는 로그 전용.
- 전달 실패 시 team-send 가 ⚠️ stdout 경고 출력 → 발신자 수동 진단 절차 진입.
- **본 §8.2.1 4단계 의무는 여전히 유효** — positive delivery 루프는 보완책이지 면제책 아님.
  실제 소실(턴 경계 레이스 1/1680)은 감지 불가 → 수동 4단계 fallback.

> ~~구 동작 (2026-06-09~2026-07-08): Hook 가 3·4단계 자동 수행 + spinner 미확인 시 Enter 보강 + exit 2 — 2026-07-09 positive delivery 전환으로 제거.~~

**디버그 로그**: `tail -20 /tmp/team-send-verify.log` 으로 본 hook 발동 이력 확인.
```

---

## 10. 후속 흐름

1. **본 ADR 승인** — 제임스 (CTO) 사인오프.
2. **마크 (Developer) 위임** — `bin/team-send-verify.sh` 구현 + `setup-team.sh` 갱신 + `skills/team-send-verify/SKILL.md` 작성. Step 0 으로 §3.1 stdin 스키마 실측 dump.
3. **정민 (QA) 테스트** — 다음 시나리오 회귀 시나리오:

   > **주의 (2026-07-09 §5.2 positive delivery 전환)**: T1~T3 는 구 verify.sh blocking 동작 기준. 현행은 §5.2 positive delivery 루프가 delivery 확인을 담당하며 verify.sh 는 로그 전용(항상 exit 0). T4~T5 는 현행에도 유효.

   - ~~(T1) 정상 spinner 확인 → exit 0~~ (구 동작)
   - ~~(T2) Enter 미발동 → 보강 후 spinner 확인 → exit 0~~ (구 동작)
   - ~~(T3) Enter 보강 후에도 미발동 → exit 2 + stderr~~ (구 동작 — exit 2 제거됨)
   - (T4) team-send 자체 실패 → hook 즉시 exit 0 (검증 skip) ✅ 현행 유효
   - (T5) Bash 명령이 team-send 아님 → hook 즉시 exit 0 ✅ 현행 유효
3. **카맥 (Performance) 측정** — ~~추가 응답 지연 < 2초 목표 검증 (sleep 2 + capture + 정규식 매칭 부담)~~ → 2026-07-09 blocking 제거로 지연 없음. positive delivery 루프 0.7s×최대 3회(잔존 시만).
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

- ~~거절~~ → **2026-07-09 채택** (positive delivery 방식으로 진화).
- 구 거절 사유("+2초 직렬 지연")는 blocking 방식 전제. 신 방식은 0.7초×최대 3회(잔존 시만) 로 지연이 작고, 잔존 없는 정상 케이스는 0.7초 후 즉시 break.
- PATTERN_ACTIVE footer 프록시 방식(Hook) 보다 입력창 잔존 직접 확인이 신뢰성 상위(네이선 Q3, 정민 6케이스 실측 통과).

### (D) 수신자 측 Hook (PreToolUse 또는 SessionStart)

- 수신자 Claude 의 input prompt 메시지 잔존 감지 + 자동 Enter.
- 구현 복잡: Claude 가 자기 input prompt 상태를 외부에서 모니터링하기 어려움.
- 발신자 측 Hook 가 시간적으로 먼저 발동하므로 발신자 측 해결이 자연.
- **거절**.

---

## 12. 결과 요약

### 초기 도입 (2026-06-09)

- **+ ** 매 team-send 호출 자동 검증 → spinner 미확인 누락 차단.
- **+ ** `setup-team.sh` 1회 실행으로 새 팀 셋업 시 자동 활성.
- **+ ** 다른 Hook 공존 — jq smart merge 보호.
- **− ** PATTERN_ACTIVE footer 방식 → 1M context reasoning 중 오경보 43.5% (2026-07-09 진단).
- **− ** 응답 지연 +2.5초 blocking.

### 2026-07-09 설계 전환 후

- **+ ** verify.sh 로그 전용 강등 → 오경보 43.5% → **0%** (실측).
- **+ ** team-send positive delivery 루프 → 입력창 잔존 직접 확인, 미제출 시 재발사 최대 3회.
- **+ ** blocking 제거 → 발신자 응답 지연 없음.
- **+ ** paste-buffer race condition 부분 해소 (1/1680 소실은 accept-loss).
- **± ** jq 의존성 유지 (verify.sh 가드 레이어 필요).
- **− ** 실제 소실(턴 경계 레이스 1/1680)은 여전히 accept-loss — retransmit-on-empty 는 중복 전달 위험.

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
| 1 | §4.2 Hook 등록 위치 (b) 사용자 전역 | **동의** (15:02) |
| 2 | §5 sleep + spinner 정규식 | **단일 PATTERN_ACTIVE 채택** (15:34 정정) — `\(([0-9]+m )?[0-9]+s · [↑↓]` + `sleep 2.5`. 초기 AND 매칭 (15:02) 은 카맥 Phase 2 측정 (15:32) 의 두 BUG 발견으로 deprecated. 본 ADR §5/§5.1 단일 패턴으로 갱신. |
| 3 | §9 `_team-workflow.md` hybrid 정책 | **동의** (15:02) — Hook 도입 후에도 매뉴얼 4단계 유지 |
| 4 | §10 후속 흐름 | **동의** (15:02) — 마크 본격 구현 즉시 진입, Step 0 (stdin 스키마) 생략 (마크 사전 조사 §2.1 완료) |

### 후속 검증 (마크 PR open 단계)

- §3 실험은 본인 (네이선) 환경 진행 — 마크·정민·카맥 페인에서 동일 동작 검증 필요. 정민 회귀 단계에 흡수.
- §9 Hook exit 2 사용자 alert 실측 — 마크 PR open 직후 정민 회귀 S4 시나리오에 흡수.
- 마크 PR open 시 본인 (네이선) 이 ADR 정합성 재점검만 진입.
