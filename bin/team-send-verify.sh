#!/usr/bin/env bash
# team-send PostToolUse Hook — 송신 후 수신자 페인 활성 검증 + Enter 보강
#
# 동작:
#   1. stdin 으로 PostToolUse JSON 페이로드 수신 (Claude Code hook 규약)
#   2. tool_name == "Bash" 이고 command 가 team-send 호출인 경우만 진입
#   3. team-send stdout 의 `pane N` 파싱 → 수신자 페인 식별
#   4. sleep 2.5 후 capture-pane → 단일 패턴 매칭 (PATTERN_ACTIVE)
#   5. 미활성 → tmux send-keys Enter 보강 → 1초 후 재확인
#   6. 여전히 미활성 → stderr 안내 + exit 2 (Esc 자동 발사 금지 — S6 β)
#
# Exit codes:
#   0 — 정상 (active 확인 또는 본 hook 비대상)
#   2 — 보강 실패 (수신자 페인 잔존 가능 — 발신자 Claude 진단 진입)
#
# 의존: jq (미설치 시 graceful exit 0 + stderr 안내), tmux, awk, grep
# 로그: /tmp/team-send-verify.log
# Refs: docs/decisions/2026-06-09-team-send-verify-hook.md (ADR)

set -uo pipefail

LOG=/tmp/team-send-verify.log
SLEEP_INITIAL=2.5        # 카맥 Phase 2 측정 (1M ctx TTFT p95 ≈ 2.5s) — 회귀 빈도 < 5% 충족
SLEEP_RECHECK=1          # Enter 보강 후 재확인 대기

# ── 1. jq 가용성 — 미설치 시 graceful degradation (S8) ────────────────────
if ! command -v jq >/dev/null 2>&1; then
    echo "[team-send-verify] jq 미설치 — 검증 skip. brew install jq 또는 apt install jq 권장." >&2
    exit 0
fi

# ── 2. stdin JSON 파싱 — tool_name 이 Bash 가 아니면 즉시 exit 0 ──────────
PAYLOAD=$(cat)
TOOL_NAME=$(jq -r '.tool_name // ""' <<<"$PAYLOAD" 2>/dev/null)
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# ── 3. team-send 명령이 아니면 즉시 exit 0 (S2) ──────────────────────────
COMMAND=$(jq -r '.tool_input.command // ""' <<<"$PAYLOAD" 2>/dev/null)
case "$COMMAND" in
    # stdin 파이프 (`cat x | team-send`) 는 §8.2 공식 사용법 — 패턴 누락 시 검증이 조용히 skip 됨.
    team-send\ *|*/team-send\ *|*\;\ team-send\ *|*\&\&\ team-send\ *|*\|\ team-send\ *) ;;
    *) exit 0 ;;
esac

# ── 4. team-send 자체 실패 시 검증 skip (S7) ─────────────────────────────
# 성공 출력 패턴: "✅ <발신> → <수신> (pane N, KB)"
STDOUT=$(jq -r '.tool_response.stdout // ""' <<<"$PAYLOAD" 2>/dev/null)
case "$STDOUT" in
    *"✅"*"→"*"(pane"*) ;;
    *) exit 0 ;;
esac

# ── 5. 발신자·수신자·pane 인덱스 파싱 ────────────────────────────────────
TARGET_PANE=$(printf '%s' "$STDOUT" | grep -oE 'pane [0-9]+' | head -1 | awk '{print $2}')
if [ -z "$TARGET_PANE" ]; then
    echo "[team-send-verify] pane 인덱스 추출 실패 — stdout: $STDOUT" >&2
    exit 0
fi

# ── 6. tmux 세션·타깃 결정 ───────────────────────────────────────────────
SESSION=$(tmux display-message -p '#S' 2>/dev/null)
if [ -z "$SESSION" ]; then
    echo "[team-send-verify] tmux 세션 식별 실패 — TMUX 환경변수 미설정 가능." >&2
    exit 0
fi
TARGET="${SESSION}:0.${TARGET_PANE}"

TS=$(date +'%Y-%m-%d %H:%M:%S')

# ── 7. 활성 판정 함수 — 단일 패턴 (CTO §14.2 정정 2026-06-09 15:34) ────────
#     PATTERN_ACTIVE: 처리 중 토큰 카운터 footer 의 괄호 + 시간 + 화살표 부분
#       예: `(15s · ↑ 234 tokens)` / `(1m 6s · ↓ 3.4k tokens)`
#     의도: active 신호 (괄호로 묶인 카운터) 매칭 + Crunched 같은 완료 메시지는
#       `Crunched for Ns · ↑ tokens` (괄호 부재) 라서 자동 차단.
#     본 단일 패턴 채택 사유 (카맥 Phase 2 발견 2026-06-09 15:32):
#       - PATTERN_VERBS 열거 방식: 실 운영 누락 (Combobulating / Transfiguring /
#         Composing) — UI 가 동사를 지속 추가 → 구조적 회귀 위험
#       - PATTERN_TOKENS 단독: 분 포맷 (1m Ns) 미지원 BUG
#       → 단일 패턴 + 분 포맷 지원으로 두 버그 동시 해소.
#     `(...)` 는 ERE 단순 그룹 (캡처 결과 미사용, 카맥 원본 `(?:...)` PCRE 비포착
#       그룹 → grep -E ERE 호환 형식으로 마크 보강).
PATTERN_ACTIVE='\(([0-9]+m )?[0-9]+s · [↑↓]'

verify_active() {
    local capture
    capture=$(tmux capture-pane -t "$TARGET" -p 2>/dev/null)
    local rc=$?
    if [ $rc -ne 0 ] || [ -z "$capture" ]; then
        return 2  # capture 실패 — caller 가 별도 처리 (S9)
    fi
    capture=$(printf '%s' "$capture" | tail -10)
    if grep -qE "$PATTERN_ACTIVE" <<<"$capture"; then
        return 0
    fi
    return 1
}

# ── 8. 초기 대기 + 1차 활성 점검 (S1 정상 케이스) ────────────────────────
sleep "$SLEEP_INITIAL"
verify_active
VERIFY_RC=$?

case $VERIFY_RC in
    0)
        echo "[$TS] OK pane=${TARGET_PANE} active (1차)" >>"$LOG" 2>/dev/null || true
        exit 0
        ;;
    2)
        echo "[$TS] FAIL pane=${TARGET_PANE} capture-pane 실패 — 페인 사라짐 가능 (S9)" >>"$LOG" 2>/dev/null || true
        cat >&2 <<EOF
[team-send-verify] ⚠️ pane=${TARGET_PANE} capture-pane 실패 — 페인 사라짐 가능.
진단: tmux list-panes -t ${SESSION}:0
EOF
        exit 2
        ;;
esac

# ── 9. Enter 보강 → 재확인 (S3 회귀 케이스) ──────────────────────────────
echo "[$TS] WARN pane=${TARGET_PANE} no active — Enter 보강 송신" >>"$LOG" 2>/dev/null || true
tmux send-keys -t "$TARGET" Enter 2>/dev/null
sleep "$SLEEP_RECHECK"
verify_active
RECHECK_RC=$?

case $RECHECK_RC in
    0)
        echo "[$TS] RECOVERED pane=${TARGET_PANE} Enter 보강 성공" >>"$LOG" 2>/dev/null || true
        exit 0
        ;;
    2)
        echo "[$TS] FAIL pane=${TARGET_PANE} 재확인 capture-pane 실패" >>"$LOG" 2>/dev/null || true
        cat >&2 <<EOF
[team-send-verify] ⚠️ pane=${TARGET_PANE} 재확인 capture-pane 실패.
진단: tmux list-panes -t ${SESSION}:0
EOF
        exit 2
        ;;
esac

# ── 10. 보강 후에도 미활성 — stderr 안내 + exit 2 (S4 / S6 β) ────────────
echo "[$TS] FAIL pane=${TARGET_PANE} Enter 보강 후도 미활성" >>"$LOG" 2>/dev/null || true
FINAL_CAPTURE=$(tmux capture-pane -t "$TARGET" -p 2>/dev/null | tail -5)
cat >&2 <<EOF
[team-send-verify] ⚠️ pane=${TARGET_PANE} 메시지 잔존 가능 — Enter 보강 후도 active 미확인.

원인 후보:
- 수신 페인이 메뉴 화면 (/help, /usage, 모달 dialog) 잔존 — Enter 가 메뉴 동작으로 처리됨
- spinner 정규식 미매칭 (Claude Code UI 변경 가능성)
- 수신자 Claude 가 별도 사유로 idle 잔존

수동 진단:
  tmux capture-pane -t ${TARGET} -p | tail -10

수동 보강 (메뉴 닫고 재발송):
  tmux send-keys -t ${TARGET} Escape
  team-send <recipient> -f <file>

capture-pane 마지막 5줄:
${FINAL_CAPTURE}
EOF
exit 2
