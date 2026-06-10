#!/bin/bash
# setup-team.sh — Claude 멀티에이전트 팀 환경 자동 구성

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SESSION=""

# ── 옵션 파싱: [세션이름] [-d|--dir <workdir>] ──
WORKDIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        -d|--dir) WORKDIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [session-name] [-d|--dir <workdir>]"
            echo "  session-name : tmux 세션 이름 (기본: team)"
            echo "  -d, --dir    : 작업 디렉터리 (기본: 현재 디렉터리)"
            exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) SESSION="$1"; shift ;;
    esac
done
SESSION="${SESSION:-team}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_DIR="$SCRIPT_DIR/roles"
WORKDIR="${WORKDIR:-$PWD}"
if [ ! -d "$WORKDIR" ]; then
    echo -e "\033[0;36m📁 작업 디렉터리 생성: $WORKDIR\033[0m"
    mkdir -p "$WORKDIR" || {
        echo -e "\033[0;31m❌ 디렉터리 생성 실패: $WORKDIR\033[0m"
        exit 1
    }
fi
WORKDIR="$(cd "$WORKDIR" && pwd)"

# ── 유틸: 파인에 패턴이 나타날 때까지 대기 ──────────────────
wait_for_pane() {
    local pane="$1" pattern="$2" timeout="${3:-30}" waited=0
    while [ $waited -lt $timeout ]; do
        tmux capture-pane -t "$pane" -p 2>/dev/null | grep -q "$pattern" && return 0
        sleep 1; waited=$((waited + 1))
    done
    return 1
}

# ── 유틸: Claude 실행 + 다이얼로그 자동 처리 ────────────────
start_claude_in_pane() {
    local pane="$1" model="${2:-claude-sonnet-4-6}" role_file="${3:-}"
    local claude_bin; claude_bin="$(command -v claude)"

    tmux send-keys -t "$pane" C-c 2>/dev/null; sleep 0.3
    tmux send-keys -t "$pane" C-u 2>/dev/null; sleep 0.2

    # 공통 워크플로(_team-workflow.md) + 역할 파일을 합쳐 단일 파일로 주입.
    local role_flag=""
    local common_file="$ROLES_DIR/_team-workflow.md"
    if [ -n "$role_file" ] && [ -f "$role_file" ]; then
        local merged_dir="$ROLES_DIR/.merged"
        mkdir -p "$merged_dir"
        local merged_file="$merged_dir/$(basename "$role_file")"
        if [ -f "$common_file" ]; then
            cat "$common_file" > "$merged_file"
            printf "\n\n---\n\n" >> "$merged_file"
            cat "$role_file" >> "$merged_file"
        else
            cat "$role_file" > "$merged_file"
        fi
        role_flag="--append-system-prompt-file \"$merged_file\""
    fi

    # team-send 헬퍼를 PATH 에 노출 (페인 간 메시지 전송용)
    tmux send-keys -t "$pane" \
        "cd \"$WORKDIR\" && export PATH=\"$SCRIPT_DIR/bin:\$PATH\" && unset CLAUDECODE && $claude_bin --model '$model' $role_flag --dangerously-skip-permissions" Enter

    # 다이얼로그 1: trust folder → Enter
    wait_for_pane "$pane" "trust this folder" 20 && {
        tmux send-keys -t "$pane" Enter; sleep 1
    }

    # 다이얼로그 2: terms of service → Down + Enter
    wait_for_pane "$pane" "I accept" 20 && {
        tmux send-keys -t "$pane" Down; sleep 0.5
        tmux send-keys -t "$pane" Enter; sleep 1
    }

    wait_for_pane "$pane" "bypass permissions" 30
}

# ── [0/4] 사전 요구사항 확인 ────────────────────────────────
echo -e "${YELLOW}[0/4] 사전 요구사항 확인...${NC}"

MISSING=()
command -v tmux   &>/dev/null || MISSING+=("tmux (sudo apt install -y tmux)")
command -v claude &>/dev/null || MISSING+=("claude (npm install -g @anthropic-ai/claude-code)")
# jq — team-send-verify hook 가 stdin JSON 파싱에 사용. 미설치 시 hook 가 graceful skip 하지만 검증 자동화가 동작 안 함.
JQ_OK=1
if ! command -v jq &>/dev/null; then
    JQ_OK=0
    echo -e "${YELLOW}  ⚠️  jq 미설치 — team-send-verify hook 가 graceful skip 됩니다.${NC}"
    echo -e "${YELLOW}     설치 권장: brew install jq (macOS) / apt install -y jq (Ubuntu)${NC}"
fi
# rsync — 스킬 디렉토리 idempotent 배포에 사용. 미설치 시 cp -R fallback.
RSYNC_OK=1
command -v rsync &>/dev/null || RSYNC_OK=0

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${RED}❌ 누락된 의존성:${NC}"
    for m in "${MISSING[@]}"; do echo "   - $m"; done
    exit 1
fi

echo "  ✅ tmux $(tmux -V | awk '{print $2}')"
echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"
[ "$JQ_OK" -eq 1 ] && echo "  ✅ jq $(jq --version 2>/dev/null)"
echo "  📂 작업 디렉터리: $WORKDIR"
echo "  🏷️  세션 이름: $SESSION"

# ── [0.5/4] team-send-verify hook + 스킬 배포 (사용자 전역) ─────────────
# 본 단계는 jq 가 있을 때만 hook 등록 진행. 스킬은 jq 없이도 배포.
echo -e "\n${YELLOW}[0.5/4] team-send-verify hook + 스킬 배포...${NC}"

HOOK_CMD="$SCRIPT_DIR/bin/team-send-verify.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
SKILL_SRC="$SCRIPT_DIR/skills/team-send-verify"
SKILL_DST="$HOME/.claude/skills/team-send-verify"

if [ ! -x "$HOOK_CMD" ]; then
    chmod +x "$HOOK_CMD" 2>/dev/null || true
fi

if [ "$JQ_OK" -eq 1 ] && [ -x "$HOOK_CMD" ]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo '{}' > "$SETTINGS_FILE"
    fi
    # 백업 (timestamp suffix). 누적되지만 사용자가 정리 가능.
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

    # smart merge — 동일 (matcher, command) 중복 추가 방지, 다른 hook 보존.
    # ADR §3.4 검증 패턴.
    PATCH_JSON=$(jq -n --arg cmd "$HOOK_CMD" '{
        hooks: {
            PostToolUse: [
                {
                    matcher: "Bash",
                    hooks: [{type: "command", command: $cmd}]
                }
            ]
        }
    }')

    MERGED=$(jq -s --argjson patch "$PATCH_JSON" '
        .[0] as $base |
        $base
        | .hooks //= {}
        | .hooks.PostToolUse =
            ([($base.hooks.PostToolUse // [])[], ($patch.hooks.PostToolUse // [])[]]
              | group_by(.matcher)
              | map({
                  matcher: .[0].matcher,
                  hooks: ([.[].hooks[]] | unique_by(.command))
              })
            )
    ' "$SETTINGS_FILE" 2>/dev/null)

    if [ -n "$MERGED" ]; then
        TMP_SETTINGS=$(mktemp)
        printf '%s\n' "$MERGED" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS_FILE"
        echo -e "  ${GREEN}✅${NC} ~/.claude/settings.json — team-send-verify hook 등록"
    else
        echo -e "  ${RED}❌${NC} jq smart merge 실패 — settings.json 백업 보존, hook 미등록"
    fi
else
    [ "$JQ_OK" -eq 0 ] && echo -e "  ${YELLOW}⏭️${NC} jq 미설치 — hook 등록 skip"
    [ ! -x "$HOOK_CMD" ] && echo -e "  ${YELLOW}⏭️${NC} $HOOK_CMD 실행 권한 없음 — hook 등록 skip"
fi

# 스킬 배포 — idempotent
if [ -d "$SKILL_SRC" ]; then
    mkdir -p "$HOME/.claude/skills"
    if [ "$RSYNC_OK" -eq 1 ]; then
        rsync -a --delete "$SKILL_SRC/" "$SKILL_DST/"
    else
        rm -rf "$SKILL_DST" && mkdir -p "$SKILL_DST" && cp -R "$SKILL_SRC/." "$SKILL_DST/"
    fi
    echo -e "  ${GREEN}✅${NC} ~/.claude/skills/team-send-verify/ 배포"
fi

# ── [1/4] 기존 세션 정리 ────────────────────────────────────
echo -e "\n${YELLOW}[1/4] 기존 세션 확인...${NC}"
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo -ne "  기존 '$SESSION' 세션이 존재합니다. 재생성하시겠습니까? [y/N]: "
    read -r CONFIRM </dev/tty
    case "$CONFIRM" in
        y|Y|yes|YES)
            tmux kill-session -t "$SESSION"
            echo "  기존 '$SESSION' 세션 종료 → 새로 생성합니다"
            ;;
        *)
            echo "  ✋ 재생성 취소. 기존 세션에 attach 합니다."
            [ -t 1 ] && exec tmux attach -t "$SESSION"
            exit 0
            ;;
    esac
fi

# ── [2/4] TMUX 세션 & 레이아웃 구성 ────────────────────────
echo -e "\n${YELLOW}[2/4] TMUX 세션 & 레이아웃 구성...${NC}"

TERM_WIDTH=$(tput cols 2>/dev/null || echo 340)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 85)
# 1:3:3 레이아웃 — CTO + 중앙 컬럼 3명 + 우측 컬럼 3명. 최소 폭 보강.
[ "${TERM_WIDTH:-0}" -lt 300 ] && TERM_WIDTH=340
[ "${TERM_HEIGHT:-0}" -lt 40 ] && TERM_HEIGHT=85

MAIN_WIDTH=180
RIGHT_AREA_WIDTH=$((TERM_WIDTH - MAIN_WIDTH - 1))

tmux new-session -d -s "$SESSION" -x "$TERM_WIDTH" -y "$TERM_HEIGHT"

# 페인 보더·타이틀 옵션을 분할 전에 활성화해야 페인 생성 시점부터 보더가 그려진다.
# pane_title 은 Claude Code 가 OSC 2 escape 로 task 설명을 덮어쓰므로 우리 역할명이 사라진다.
# 회피책: per-pane user option @role 에 역할명을 저장하고 보더 포맷이 @role 을 표시.
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{@role} "
tmux set-option -t "$SESSION" allow-rename off

# 레이아웃 (1:3:3):
#   ┌─────────┬──────────┬──────────┐
#   │         │ 네이선   │ 수진     │  ← top row
#   │ 제임스  ├──────────┼──────────┤
#   │ (CTO)   │ 마크     │ 정민     │  ← mid row
#   │         ├──────────┼──────────┤
#   │         │ 수영     │ 카맥     │  ← bot row
#   └─────────┴──────────┴──────────┘
# tmux 는 페인 인덱스를 시각적 row-major 순서로 재정렬하므로
# 최종 인덱스: 0=제임스, 1=네이선, 2=수진, 3=마크, 4=정민, 5=수영, 6=카맥.
# 분할 도중 인덱스 변동을 피하기 위해 페인 ID(#{pane_id}) 로 추적한다.

P_JAMES=$(tmux display-message -p -t "$SESSION:0.0" '#{pane_id}')

# Phase 1: 좌측 메인 + 우측 영역
P_MIDCOL_TOP=$(tmux split-window -h -P -F '#{pane_id}' -t "$P_JAMES" -l "$RIGHT_AREA_WIDTH")

# Phase 2: 중앙 컬럼을 3행으로 분할
P_MIDCOL_MID=$(tmux split-window -v -P -F '#{pane_id}' -t "$P_MIDCOL_TOP" -p 67)
P_MIDCOL_BOT=$(tmux split-window -v -P -F '#{pane_id}' -t "$P_MIDCOL_MID" -p 50)

# Phase 3: 각 행을 좌(중앙 컬럼) + 우(오른쪽 컬럼) 으로 분할
P_RIGHTCOL_TOP=$(tmux split-window -h -P -F '#{pane_id}' -t "$P_MIDCOL_TOP" -p 50)
P_RIGHTCOL_MID=$(tmux split-window -h -P -F '#{pane_id}' -t "$P_MIDCOL_MID" -p 50)
P_RIGHTCOL_BOT=$(tmux split-window -h -P -F '#{pane_id}' -t "$P_MIDCOL_BOT" -p 50)

# 시각적 row-major 인덱스 순서로 멤버 배치 (페인 ID 배열)
#   0=제임스 / 1=네이선 / 2=수진 / 3=마크 / 4=정민 / 5=수영 / 6=카맥
PANE_IDS=(
    "$P_JAMES"
    "$P_MIDCOL_TOP"
    "$P_RIGHTCOL_TOP"
    "$P_MIDCOL_MID"
    "$P_RIGHTCOL_MID"
    "$P_MIDCOL_BOT"
    "$P_RIGHTCOL_BOT"
)

# 파인 역할명 설정 — per-pane user option @role (Claude OSC 2 영향 없음)
tmux set-option -p -t "$P_JAMES"        @role "제임스 CTO"
tmux set-option -p -t "$P_MIDCOL_TOP"   @role "네이선 Architect"
tmux set-option -p -t "$P_RIGHTCOL_TOP" @role "수진 Researcher"
tmux set-option -p -t "$P_MIDCOL_MID"   @role "마크저커버그 Developer"
tmux set-option -p -t "$P_RIGHTCOL_MID" @role "정민 QA·Reviewer"
tmux set-option -p -t "$P_MIDCOL_BOT"   @role "수영 UI/UX Designer"
tmux set-option -p -t "$P_RIGHTCOL_BOT" @role "카맥 Performance Engineer"

echo "  ✅ 레이아웃 구성 완료 (7 panes, 1:3:3)"

# ── 페인 매핑 자가 검증 ────────────────────────────────────
# team-send 의 이름→인덱스 매핑은 row-major 시각 인덱스 가정에 의존.
# tmux 동작 차이·레이아웃 변경으로 어긋나면 메시지가 다른 멤버에게 오배달되므로
# Claude 기동 전에 인덱스↔역할 일치를 검증한다.
EXPECTED_ROLES=("제임스 CTO" "네이선 Architect" "수진 Researcher" "마크저커버그 Developer" "정민 QA·Reviewer" "수영 UI/UX Designer" "카맥 Performance Engineer")
MAPPING_OK=1
for i in 0 1 2 3 4 5 6; do
    actual="$(tmux display-message -p -t "$SESSION:0.$i" '#{@role}' 2>/dev/null)"
    if [ "$actual" != "${EXPECTED_ROLES[$i]}" ]; then
        echo -e "  ${RED}❌ pane $i: 기대 '${EXPECTED_ROLES[$i]}' ≠ 실제 '$actual'${NC}"
        MAPPING_OK=0
    fi
done
if [ "$MAPPING_OK" -eq 1 ]; then
    echo -e "  ${GREEN}✅ 페인 인덱스 ↔ 역할 매핑 일치 (team-send 기준)${NC}"
else
    echo -e "  ${RED}⚠️  매핑 불일치 — team-send 가 잘못된 페인으로 송신됩니다. 세션을 종료하고 레이아웃을 수정하세요.${NC}"
    tmux kill-session -t "$SESSION"
    exit 1
fi

# ── [3/4] Claude 자동 실행 ──────────────────────────────────
echo -e "\n${YELLOW}[3/4] Claude 실행 중... (파인당 최대 1분)${NC}"

# MEMBER_NAMES/MODELS 순서는 PANE_IDS 와 동일한 row-major 시각 인덱스를 따른다.
#   0=제임스 / 1=네이선 / 2=수진 / 3=마크 / 4=정민 / 5=수영 / 6=카맥
# 모델 배정 원칙 (사용 패턴 측정 기반, 2026-05-20 갱신):
#   - Opus 4.8: 의사결정·아키텍처·구현 품질·머지 게이트 (영향 大)
#   - Sonnet 4.6 (1M): 고빈도 반복 작업 + 큰 컨텍스트 필요 (예: 측정·프로파일링)
#   - Haiku 4.5: 단순 조회·비교·저활동 멤버 (Sonnet 의 90% 성능, 약 1/3 비용)
MEMBER_NAMES=("제임스" "네이선" "수진" "마크저커버그" "정민" "수영" "카맥")
MEMBER_MODELS=(
    "claude-opus-4-8"        # 제임스 CTO — 전략 결정·릴리스 사인오프·모니터링
    "claude-opus-4-8"        # 네이선 Architect — 아키텍처 결정·ADR
    "claude-sonnet-4-6[1m]"  # 수진 Researcher — 저활동 (PR 0건). 단순 문서 조회·비교에 충분
    "claude-opus-4-8"        # 마크 Developer — 구현 품질 머지 게이트의 입구. 고빈도 코드 작성
    "claude-opus-4-8"        # 정민 QA·Reviewer — 머지 게이트 (CRITICAL 누락 비용 ↑)
    "claude-sonnet-4-6[1m]"  # 수영 UI/UX — 현 백엔드 프로젝트 한정 (UI 작업 최소). 프런트 프로젝트면 Sonnet 으로 복귀
    "claude-sonnet-4-6[1m]"  # 카맥 Performance — 측정 146회 (최다). 1M 컨텍스트로 auto-compact 완화
)

for i in 0 1 2 3 4 5 6; do
    name="${MEMBER_NAMES[$i]}"
    pane_id="${PANE_IDS[$i]}"
    role_file="$ROLES_DIR/$name.md"
    if [ ! -f "$role_file" ]; then
        echo -e "  ${YELLOW}⚠️  역할 파일 없음: $role_file (역할 미주입)${NC}"
        role_file=""
    fi
    echo -n "  Pane $i ($name): "
    start_claude_in_pane "$pane_id" "${MEMBER_MODELS[$i]}" "$role_file"

    tmux capture-pane -t "$pane_id" -p 2>/dev/null | grep -q "bypass permissions" \
        && echo -e "${GREEN}✅ 준비 완료${NC}" \
        || echo -e "${RED}⚠️  타임아웃 — 수동 확인 필요${NC}"
done

# ── [4/4] 완료 ──────────────────────────────────────────────
echo -e "\n${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   ✅ 팀 환경 구성 완료!              ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# 터미널에서 직접 실행한 경우 자동 attach
[ -t 1 ] && tmux attach -t "$SESSION"
