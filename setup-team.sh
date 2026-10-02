#!/bin/bash
# setup-team.sh — Claude 멀티에이전트 팀 환경 자동 구성

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SESSION=""

# ── 옵션 파싱: [세션이름] [-d|--dir <workdir>] [-c|--config <팀 이름|설정 파일>] ──
WORKDIR=""
MEMBERS_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -d|--dir) WORKDIR="$2"; shift 2 ;;
        -c|--config) MEMBERS_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [session-name] [-d|--dir <workdir>] [-c|--config <팀 이름|설정 파일>]"
            echo "  session-name : tmux 세션 이름 (기본: team)"
            echo "  -d, --dir    : 작업 디렉터리 (기본: 현재 디렉터리)"
            echo "  -c, --config : 팀 이름(teams/<이름>.conf) 또는 설정 파일 경로 (기본: idea — 아이디어 팀)"
            echo "                 팀 목록: $(cd "$(dirname "$0")/teams" 2>/dev/null && ls *.conf 2>/dev/null | sed 's/\.conf$//' | tr '\n' ' ')"
            exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) SESSION="$1"; shift ;;
    esac
done
SESSION="${SESSION:-team}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_DIR="$SCRIPT_DIR/roles"

# 멤버 설정 로드 — 형식 오류는 tmux 세션을 만들기 전에 실패시킨다.
. "$SCRIPT_DIR/lib/members.sh"
# 팀 설정: 기본은 아이디어 팀. 이름만 주면 teams/<이름>.conf, 경로를 주면 그 파일.
MEMBERS_FILE="${MEMBERS_FILE:-idea}"
case "$MEMBERS_FILE" in
    */*|*.conf) ;;
    *) MEMBERS_FILE="$SCRIPT_DIR/teams/$MEMBERS_FILE.conf" ;;
esac
[ -f "$MEMBERS_FILE" ] && MEMBERS_FILE="$(cd "$(dirname "$MEMBERS_FILE")" && pwd)/$(basename "$MEMBERS_FILE")"
load_members "$MEMBERS_FILE" || exit 1
WORKDIR="${WORKDIR:-$PWD}"
if [ ! -d "$WORKDIR" ]; then
    echo -e "\033[0;36m📁 작업 디렉터리 생성: $WORKDIR\033[0m"
    mkdir -p "$WORKDIR" || {
        echo -e "\033[0;31m❌ 디렉터리 생성 실패: $WORKDIR\033[0m"
        exit 1
    }
fi
WORKDIR="$(cd "$WORKDIR" && pwd)"

# ── 유틸: 엔진별 준비 완료 화면 패턴 ───────────────────────
ready_pattern() {
    case "$1" in
        codex) echo "for shortcuts" ;;
        *)     echo "bypass permissions" ;;
    esac
}

# ── 유틸: 멤버 정체 블록 — 역할 지시 맨 앞에 붙는다 ────────────
# 페어처럼 여러 멤버가 같은 역할 파일을 쓸 때 각자 자기 이름·엔진·상대를 알게 한다.
member_identity() {
    local i="$1" j=0 partners="" eng
    while [ $j -lt $M_COUNT ]; do
        if [ $j -ne $i ] && [ "${M_ROLE[$j]}" = "${M_ROLE[$i]}" ]; then
            [ "${M_ENGINE[$j]}" = "codex" ] && eng="Codex" || eng="Claude"
            partners="${partners:+$partners, }${M_NAME[$j]} ($eng)"
        fi
        j=$((j + 1))
    done
    [ "${M_ENGINE[$i]}" = "codex" ] && eng="Codex" || eng="Claude"
    cat <<EOF
## 당신의 정체 (setup-team.sh 가 팀 설정으로 생성)

- 이름: **${M_NAME[$i]}** — team-send 수신자 이름${M_ALIASES[$i]:+ (별칭: ${M_ALIASES[$i]})}
- 엔진: **$eng** (${M_MODEL[$i]}, effort ${M_EFFORT[$i]})
- 프로젝트: ${TEAM_PROJECT:-지정 없음}
- tmux 창: ${M_WINDOW[$i]}
- 역할 파일: roles/${M_ROLE[$i]}.md
- 같은 역할의 페어: ${partners:-없음}
- 부여된 플러그인: ${M_PLUGINS[$i]:-없음} (팀 설정 플러그인 열 — 이 목록 밖의 스킬·플러그인이 설치돼 있다고 가정하지 않는다)
- 팀 구성은 \`team-send -h\`, 상태는 \`team-status\` 로 확인한다.

---

EOF
}

# ── 유틸: 멤버별 플러그인 (팀 설정 플러그인 열) ─────────────
# Claude: 공식 마켓플레이스 사본의 플러그인 폴더를 --plugin-dir 로 그 멤버 세션에만 로드 (전역 활성화 안 함).
# Codex : openai-curated-remote 플러그인을 설치해 두고 전역은 끈 상태(~/.codex/config.toml enabled=false)에서
#         멤버마다 -c plugins.<이름>@openai-curated-remote.enabled=true 로 켠다 (키에 따옴표를 쓰면 적용되지 않음).
CLAUDE_MARKET="$HOME/.claude/plugins/marketplaces/claude-plugins-official"
CODEX_PLUGIN_MARKET="openai-curated-remote"
CODEX_PLUGIN_CACHE="${CODEX_HOME:-$HOME/.codex}/plugins/cache/$CODEX_PLUGIN_MARKET"
# check_plugins — 기동 전 점검: 팀 설정의 플러그인이 실제로 있는지 (없는 것은 경고 후 건너뜀)
check_plugins() {
    local i=0 p
    while [ $i -lt $M_COUNT ]; do
        for p in ${M_PLUGINS[$i]}; do
            if [ "${M_ENGINE[$i]}" = "codex" ]; then
                [ -d "$CODEX_PLUGIN_CACHE/$p" ] || echo -e "  ${YELLOW}⚠️  ${M_NAME[$i]}: Codex 플러그인 '$p' 미설치 — codex plugin add $p@$CODEX_PLUGIN_MARKET${NC}"
            else
                [ -d "$CLAUDE_MARKET/plugins/$p" ] || [ -d "$CLAUDE_MARKET/external_plugins/$p" ] \
                    || echo -e "  ${YELLOW}⚠️  ${M_NAME[$i]}: Claude 플러그인 '$p' 가 공식 마켓플레이스 사본에 없음 ($CLAUDE_MARKET)${NC}"
            fi
        done
        i=$((i + 1))
    done
}

# 팀이 관리하는 Codex 플러그인 = 모든 팀 설정(teams/*.conf + 이번 설정)의 codex 멤버 플러그인 열 합집합.
# 대화형 Codex 는 원격 설치 플러그인의 enabled 설정을 따르지 않으므로(2026-10-02 확인), 멤버에게 부여되지 않은
# 관리 대상 플러그인의 스킬을 skills.config 로 경로 단위 비활성화해 멤버별 부여를 실현한다.
codex_managed_plugins() {
    awk -F'|' '!/^[[:space:]]*[#@[]/ && NF >= 8 {
        e = $4; gsub(/[[:space:]]/, "", e)
        if (e == "codex") { n = split($8, a, /[[:space:]]+/); for (k = 1; k <= n; k++) if (a[k] != "") print a[k] }
    }' "$SCRIPT_DIR"/teams/*.conf "$MEMBERS_FILE" 2>/dev/null | sort -u
}

# member_plugin_args <멤버 인덱스> — 엔진에 맞는 플러그인 인자를 한 줄에 하나씩 출력
member_plugin_args() {
    local i="$1" p dir off="" f
    if [ "${M_ENGINE[$i]}" = "codex" ]; then
        for p in $(codex_managed_plugins); do
            case " ${M_PLUGINS[$i]} " in *" $p "*) continue ;; esac
            [ -d "$CODEX_PLUGIN_CACHE/$p" ] || continue
            while IFS= read -r f; do
                [ -n "$f" ] && off="${off:+$off,}{path=\"$f\",enabled=false}"
            done <<EOF
$(find "$CODEX_PLUGIN_CACHE/$p" -name SKILL.md 2>/dev/null)
EOF
        done
        [ -n "$off" ] && { echo "-c"; echo "skills.config=[$off]"; }
    fi
    for p in ${M_PLUGINS[$i]}; do
        if [ "${M_ENGINE[$i]}" = "codex" ]; then
            if [ -d "$CODEX_PLUGIN_CACHE/$p" ]; then
                echo "-c"; echo "plugins.$p@$CODEX_PLUGIN_MARKET.enabled=true"
            fi
        else
            dir=""
            [ -d "$CLAUDE_MARKET/plugins/$p" ] && dir="$CLAUDE_MARKET/plugins/$p"
            [ -z "$dir" ] && [ -d "$CLAUDE_MARKET/external_plugins/$p" ] && dir="$CLAUDE_MARKET/external_plugins/$p"
            [ -n "$dir" ] && { echo "--plugin-dir"; echo "$dir"; }
        fi
    done
}

# ── 유틸: 멤버 실행 (claude | codex) + 다이얼로그 자동 처리 ──
start_member_in_pane() {
    local pane="$1" idx="$2" role_file="${3:-}"
    local engine="${M_ENGINE[$idx]}" model="${M_MODEL[$idx]}" effort="${M_EFFORT[$idx]}"

    tmux send-keys -t "$pane" C-c 2>/dev/null; sleep 0.3
    tmux send-keys -t "$pane" C-u 2>/dev/null; sleep 0.2

    # 정체 블록 + 공통 워크플로(_team-workflow.md) + 역할 파일을 멤버별 단일 파일로 합쳐 주입.
    # 파일 이름은 멤버 이름 — 페어가 같은 역할 파일을 써도 서로 덮어쓰지 않는다.
    local common_file="$ROLES_DIR/_team-workflow.md"
    # 세션별 폴더 — 여러 팀(세션)이 같은 멤버 이름을 써도 서로 덮어쓰지 않는다.
    local merged_dir="$ROLES_DIR/.merged/$SESSION"
    local merged_file="$merged_dir/${M_NAME[$idx]}.md"
    mkdir -p "$merged_dir"
    {
        member_identity "$idx"
        if [ -f "$common_file" ]; then
            cat "$common_file"
            [ -n "$role_file" ] && printf "\n\n---\n\n"
        fi
        [ -n "$role_file" ] && cat "$role_file"
    } > "$merged_file"

    # team-send 헬퍼를 PATH 에 노출 (페인 간 메시지 전송용)
    # TEAM_MEMBER·TEAM_ENGINE: 체크포인트 훅(bin/team-checkpoint)이 멤버를 식별하는 데 쓴다.
    # 한글 이름은 printf %q 로 감싸면 페인의 zsh 가 바이트를 잘못 해석하므로 큰따옴표로만 감싼다.
    local prefix="cd \"$WORKDIR\" && export PATH=\"$SCRIPT_DIR/bin:\$PATH\" TEAM_MEMBER=\"${M_NAME[$idx]}\" TEAM_ENGINE=$engine TEAM_SESSION=\"$SESSION\" && unset CLAUDECODE"
    # security-guidance: 여러 멤버가 한 작업 폴더를 공유하므로 턴 종료 LLM 리뷰는 끈다 (플러그인 README 권장 — 다른 멤버가 HEAD 를 옮길 수 있음)
    case " ${M_PLUGINS[$idx]} " in *" security-guidance "*) prefix="$prefix && export ENABLE_STOP_REVIEW=0" ;; esac
    local checkpoint="$SCRIPT_DIR/bin/team-checkpoint"
    local plugin_args=()
    while IFS= read -r line; do plugin_args[${#plugin_args[@]}]="$line"; done <<EOF
$(member_plugin_args "$idx")
EOF
    [ -n "${plugin_args[0]:-}" ] || plugin_args=()

    if [ "$engine" = "codex" ]; then
        # Codex 는 --append-system-prompt-file 이 없어 developer_instructions 설정으로 주입한다.
        # 역할 지시(~45KB)를 send-keys 로 타이핑하지 않도록 실행 스크립트를 만들어 호출한다.
        # TOML 멀티라인 리터럴 문자열(''') 은 이스케이프가 필요 없지만, 본문에 ''' 가 있으면 깨진다.
        local tq="'''"
        local launcher="$merged_dir/${M_NAME[$idx]}.codex.sh"
        local codex_cmd
        # --search: 웹 검색 사용 (조사 역할). check_for_update_on_startup=false: 기동 시 업데이트 안내가 뜨면
        # 자동 입력(Enter)이 "Update now" 로 선택돼 전역 npm 업데이트가 실행되므로 끈다 (업데이트는 사용자가 직접).
        # --no-daemon: 대화형 Codex 는 공유 백그라운드 서버에 붙고 플러그인 상태가 서버 단위로 잡혀, 멤버별 플러그인 지정이
        # 새어 나간다(2026-10-02 확인). 멤버마다 독립 프로세스로 띄워 멤버별 설정(-c)이 그대로 적용되게 한다.
        codex_cmd="exec $(printf '%q' "$(command -v codex)") --dangerously-bypass-approvals-and-sandbox --no-daemon --search -c check_for_update_on_startup=false -m $(printf '%q' "$model") -c model_reasoning_effort=$(printf '%q' "$effort")"
        if [ -n "$merged_file" ]; then
            if grep -qF "$tq" "$merged_file"; then
                echo -e "${RED}❌ $merged_file 에 $tq 가 있어 Codex 에 주입할 수 없습니다${NC}"
                return 1
            fi
            codex_cmd="$codex_cmd -c \"developer_instructions=$tq\$(cat $(printf '%q' "$merged_file"))$tq\""
        fi
        # 체크포인트 훅: PreCompact 에서 저장 → 정리 후 SessionStart(compact) 또는 다음 UserPromptSubmit 에서 복구 지시 1회 주입.
        # (Codex PreCompact/PostCompact 는 additionalContext 를 받지 않고, compact 후 SessionStart 가 오지 않는 경우가 있음 — 2026-10-02 확인) -c 로 넣은 훅은 신뢰 저장이 없으므로
        # --dangerously-bypass-hook-trust 로 이 실행에서만 신뢰 확인을 건너뛴다 (~/.codex/hooks.json 의 사용자 훅도 함께 실행된다).
        codex_cmd="$codex_cmd --dangerously-bypass-hook-trust"
        codex_cmd="$codex_cmd -c $(printf '%q' "hooks.PreCompact=[{hooks=[{type=\"command\",command=\"$checkpoint pre\",timeout=30}]}]")"
        codex_cmd="$codex_cmd -c $(printf '%q' "hooks.SessionStart=[{matcher=\"compact\",hooks=[{type=\"command\",command=\"$checkpoint post\",timeout=30}]}]")"
        codex_cmd="$codex_cmd -c $(printf '%q' "hooks.UserPromptSubmit=[{hooks=[{type=\"command\",command=\"$checkpoint post\",timeout=30}]}]")"
        local a
        for a in "${plugin_args[@]}"; do codex_cmd="$codex_cmd $(printf '%q' "$a")"; done
        printf '#!/bin/bash\n%s\n' "$codex_cmd" > "$launcher"
        tmux send-keys -t "$pane" "$prefix && bash \"$launcher\"" Enter

        # 다이얼로그: 폴더 신뢰 → Enter (1. Trust and continue)
        #            훅 검토   → Esc (이번 실행은 신뢰 없이 건너뜀 — 사용자 훅 신뢰는 사용자가 직접 결정)
        local waited=0 screen
        while [ $waited -lt 60 ]; do
            screen="$(tmux capture-pane -t "$pane" -p 2>/dev/null)"
            case "$screen" in
                *"for shortcuts"*) return 0 ;;
                *"Trust this folder"*) tmux send-keys -t "$pane" Enter; sleep 1 ;;
                *"Hooks need review"*) tmux send-keys -t "$pane" Escape; sleep 1 ;;
            esac
            sleep 1; waited=$((waited + 1))
        done
        return 1
    fi

    # 체크포인트 훅: PreCompact 에서 저장, 정리 후 SessionStart(source=compact) 에서 복구 지시 주입.
    # --settings 로 이 멤버 세션에만 등록한다 (사용자 전역 settings.json 은 건드리지 않음).
    local settings="$merged_dir/${M_NAME[$idx]}.settings.json"
    printf '{"hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"%s pre","timeout":30}]}],"SessionStart":[{"matcher":"compact","hooks":[{"type":"command","command":"%s post","timeout":30}]}]}}\n' \
        "$checkpoint" "$checkpoint" > "$settings"
    local launcher="$merged_dir/${M_NAME[$idx]}.claude.sh"
    local claude_cmd a
    claude_cmd="exec $(printf '%q' "$(command -v claude)") --model $(printf '%q' "$model") --effort $(printf '%q' "$effort")"
    claude_cmd="$claude_cmd --append-system-prompt-file $(printf '%q' "$merged_file") --settings $(printf '%q' "$settings")"
    for a in "${plugin_args[@]}"; do claude_cmd="$claude_cmd $(printf '%q' "$a")"; done
    claude_cmd="$claude_cmd --dangerously-skip-permissions"
    printf '#!/bin/bash\n%s\n' "$claude_cmd" > "$launcher"
    tmux send-keys -t "$pane" "$prefix && bash \"$launcher\"" Enter

    # 다이얼로그 자동 처리 — 선택 항목을 확인한 뒤 고른다.
    #   폴더 신뢰: 기본 선택이 "No, exit" 이므로 Enter 만 보내면 Claude 가 종료된다.
    #             커서(❯)가 "Yes, I trust this folder" 에 올 때까지 Down 후 Enter.
    #   약관 동의: Down + Enter (구버전 화면)
    local waited=0 screen
    while [ $waited -lt 60 ]; do
        screen="$(tmux capture-pane -t "$pane" -p 2>/dev/null)"
        case "$screen" in
            *"Yes, I trust this folder"*)
                if printf '%s\n' "$screen" | grep -q "❯.*Yes, I trust this folder"; then
                    tmux send-keys -t "$pane" Enter
                else
                    tmux send-keys -t "$pane" Down
                fi
                sleep 1 ;;
            *"I accept"*)
                tmux send-keys -t "$pane" Down; sleep 0.5
                tmux send-keys -t "$pane" Enter; sleep 1 ;;
            *"bypass permissions"*) return 0 ;;
        esac
        sleep 1; waited=$((waited + 1))
    done
    return 1
}

# ── [0/4] 사전 요구사항 확인 ────────────────────────────────
echo -e "${YELLOW}[0/4] 사전 요구사항 확인...${NC}"

MISSING=()
command -v tmux   &>/dev/null || MISSING+=("tmux (sudo apt install -y tmux)")
# 엔진 CLI 는 팀 설정에서 실제로 쓰는 것만 요구한다.
case " ${M_ENGINE[*]} " in *" claude "*)
    command -v claude &>/dev/null || MISSING+=("claude (npm install -g @anthropic-ai/claude-code)") ;; esac
case " ${M_ENGINE[*]} " in *" codex "*)
    command -v codex &>/dev/null || MISSING+=("codex (npm install -g @openai/codex)") ;; esac
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
command -v claude &>/dev/null && echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"
command -v codex  &>/dev/null && echo "  ✅ $(codex --version 2>/dev/null | head -1)"
[ "$JQ_OK" -eq 1 ] && echo "  ✅ jq $(jq --version 2>/dev/null)"
[ "$JQ_OK" -eq 1 ] || echo -e "  ${YELLOW}⚠️  jq 미설치 — 체크포인트 훅·Codex 한도 조회가 동작하지 않습니다${NC}"
check_plugins
echo "  📂 작업 디렉터리: $WORKDIR"
echo "  🏷️  세션 이름: $SESSION"
echo "  👥 멤버 설정: $MEMBERS_FILE (${M_COUNT}명)"
[ -n "$TEAM_PROJECT" ] && echo "  🎯 프로젝트: $TEAM_PROJECT"

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

# 팀 설정의 [창이름] 구획마다 tmux 창 하나. 구획이 없으면 창 'team' 하나.
# 창마다 레이아웃: 그 창의 첫 멤버는 좌측 메인, 나머지는 우측 2열 그리드에 행 우선 배치.
#   ┌─────────┬──────────┬──────────┐
#   │         │ 2번째    │ 3번째    │
#   │ 첫 멤버 ├──────────┼──────────┤
#   │ (메인)  │ 4번째    │ 5번째    │
#   │         ├──────────┼──────────┤
#   │         │ 6번째    │ 7번째    │   ← 우측 인원이 홀수면 마지막 행은 1칸
#   └─────────┴──────────┴──────────┘
# 페인은 ID(#{pane_id}) 로 추적하고 @member 태그로 찾으므로 tmux 인덱스·창 번호와 무관하다.
# 같은 창의 멤버는 팀 설정에서 연속이다 (lib/members.sh 가 중복 구획을 거부).

# 창별 우측 행 수 중 최댓값으로 터미널 최소 높이를 정한다.
MAX_ROWS=0
w=0
while [ $w -lt $W_COUNT ]; do
    n=0; i=0
    while [ $i -lt $M_COUNT ]; do [ "${M_WINDOW[$i]}" = "${W_NAME[$w]}" ] && n=$((n + 1)); i=$((i + 1)); done
    rows=$(( n / 2 )); [ $rows -gt $MAX_ROWS ] && MAX_ROWS=$rows
    w=$((w + 1))
done

TERM_WIDTH=$(tput cols 2>/dev/null || echo 340)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 85)
# 최소 크기 보강 — 행당 최소 14줄 확보
MIN_HEIGHT=$(( MAX_ROWS * 14 )); [ "$MIN_HEIGHT" -lt 85 ] && MIN_HEIGHT=85
[ "${TERM_WIDTH:-0}" -lt 300 ] && TERM_WIDTH=340
[ "${TERM_HEIGHT:-0}" -lt "$MIN_HEIGHT" ] && TERM_HEIGHT=$MIN_HEIGHT

MAIN_WIDTH=180
RIGHT_AREA_WIDTH=$((TERM_WIDTH - MAIN_WIDTH - 1))

# build_window <첫 페인 ID> <첫 멤버 인덱스> <멤버 수> — 창 하나를 분할하고 PANE_IDS 에 멤버 순서대로 추가
build_window() {
    local first="$1" start="$2" count="$3"
    local right=$((count - 1)) rows=$(( count / 2 )) r
    local row_ids=()
    PANE_IDS[$start]="$first"
    [ $rows -gt 0 ] || return 0
    # Phase 1: 좌측 메인 + 우측 영역
    row_ids[0]=$(tmux split-window -h -P -F '#{pane_id}' -t "$first" -l "$RIGHT_AREA_WIDTH")
    # Phase 2: 우측 영역을 rows 행으로 균등 분할 (남은 영역에서 아래쪽을 계속 떼어냄)
    r=1
    while [ $r -lt $rows ]; do
        row_ids[$r]=$(tmux split-window -v -P -F '#{pane_id}' -t "${row_ids[$((r - 1))]}" -p $(( 100 * (rows - r) / (rows - r + 1) )))
        r=$((r + 1))
    done
    # Phase 3: 각 행을 좌·우로 분할 (마지막 행은 남은 멤버가 1명이면 분할하지 않음)
    r=0
    while [ $r -lt $rows ]; do
        PANE_IDS[$((start + 1 + 2 * r))]="${row_ids[$r]}"
        if [ $(( 2 * r + 2 )) -le $right ]; then
            PANE_IDS[$((start + 2 + 2 * r))]=$(tmux split-window -h -P -F '#{pane_id}' -t "${row_ids[$r]}" -p 50)
        fi
        r=$((r + 1))
    done
}

PANE_IDS=()
WINDOW_IDS=()
start=0
w=0
while [ $w -lt $W_COUNT ]; do
    count=0
    while [ $((start + count)) -lt $M_COUNT ] && [ "${M_WINDOW[$((start + count))]}" = "${W_NAME[$w]}" ]; do
        count=$((count + 1))
    done
    if [ $w -eq 0 ]; then
        tmux new-session -d -s "$SESSION" -n "${W_NAME[$w]}" -x "$TERM_WIDTH" -y "$TERM_HEIGHT"
        # team-send 가 이 세션의 멤버 설정을 찾을 수 있도록 세션 옵션에 기록
        tmux set-option -t "$SESSION" @team_members_file "$MEMBERS_FILE"
        # 첫 페인 — tmux base-index 설정과 무관하게 세션의 활성 페인으로 잡는다.
        first="$(tmux display-message -p -t "$SESSION" '#{pane_id}')"
    else
        first="$(tmux new-window -d -P -F '#{pane_id}' -t "$SESSION:" -n "${W_NAME[$w]}")"
    fi
    WINDOW_IDS[$w]="$(tmux display-message -p -t "$first" '#{window_id}')"

    # 페인 보더·타이틀 옵션(창 옵션)을 분할 전에 활성화해야 페인 생성 시점부터 보더가 그려진다.
    # pane_title 은 Claude Code 가 OSC 2 escape 로 task 설명을 덮어쓰므로 우리 역할명이 사라진다.
    # 회피책: per-pane user option @role 에 역할명을 저장하고 보더 포맷이 @role 을 표시.
    tmux set-option -w -t "${WINDOW_IDS[$w]}" pane-border-status top
    tmux set-option -w -t "${WINDOW_IDS[$w]}" pane-border-format " #{@role} "
    tmux set-option -w -t "${WINDOW_IDS[$w]}" allow-rename off
    tmux set-option -w -t "${WINDOW_IDS[$w]}" automatic-rename off

    build_window "$first" "$start" "$count"
    echo "  ✅ 창 '${W_NAME[$w]}' — ${count}명 (메인 1 + 우측 $(( count / 2 ))행 × 2열)"
    start=$((start + count))
    w=$((w + 1))
done
# 첫 창을 띄운 상태로 attach
tmux select-window -t "${WINDOW_IDS[0]}"

# 페인 태그 — @role: 보더 표시용 라벨 (Claude OSC 2 영향 없음)
#             @member: 팀 설정 행 번호. team-send·team-status 는 tmux 인덱스가 아니라 이 태그로 페인을 찾는다.
#             @engine: claude | codex. team-status 가 엔진별로 컨텍스트·사용 한도를 읽는 데 쓴다.
i=0
while [ $i -lt $M_COUNT ]; do
    tmux set-option -p -t "${PANE_IDS[$i]}" @role "${M_LABEL[$i]}"
    tmux set-option -p -t "${PANE_IDS[$i]}" @member "$i"
    tmux set-option -p -t "${PANE_IDS[$i]}" @engine "${M_ENGINE[$i]}"
    i=$((i + 1))
done

echo "  ✅ 레이아웃 구성 완료 (${M_COUNT} panes, ${W_COUNT}개 창)"

# ── 페인 매핑 자가 검증 ────────────────────────────────────
# team-send 는 @member 태그로 수신 페인을 찾는다. 태그가 어긋나면 메시지가 다른 멤버에게
# 오배달되므로 기동 전에 멤버마다 태그 페인이 정확히 하나이고 라벨이 일치하는지 검증한다.
MAPPING_OK=1
i=0
while [ $i -lt $M_COUNT ]; do
    found="$(tmux list-panes -s -t "$SESSION" -F '#{@member}' | grep -cx "$i")"
    pid="$(member_pane_id "$SESSION" "$i")"
    actual="$(tmux display-message -p -t "${pid:-none}" '#{@role}' 2>/dev/null)"
    if [ "$found" -ne 1 ] || [ "$actual" != "${M_LABEL[$i]}" ]; then
        echo -e "  ${RED}❌ member $i: 태그 페인 ${found}개, 기대 '${M_LABEL[$i]}' ≠ 실제 '$actual'${NC}"
        MAPPING_OK=0
    fi
    i=$((i + 1))
done
if [ "$MAPPING_OK" -eq 1 ]; then
    echo -e "  ${GREEN}✅ 멤버 ↔ 페인 태그 매핑 일치 (team-send 기준)${NC}"
else
    echo -e "  ${RED}⚠️  매핑 불일치 — team-send 가 잘못된 페인으로 송신됩니다. 세션을 종료하고 레이아웃을 수정하세요.${NC}"
    tmux kill-session -t "$SESSION"
    exit 1
fi

# ── [3/4] Claude 자동 실행 ──────────────────────────────────
echo -e "\n${YELLOW}[3/4] 멤버 실행 중 (Claude / Codex)... (페인당 최대 1분)${NC}"

# 멤버별 엔진·모델·effort·역할 파일은 팀 설정(teams/*.conf)이 단일 소스.
i=0
while [ $i -lt $M_COUNT ]; do
    pane_id="${PANE_IDS[$i]}"
    role_file="$ROLES_DIR/${M_ROLE[$i]}.md"
    if [ ! -f "$role_file" ]; then
        echo -e "  ${YELLOW}⚠️  역할 파일 없음: $role_file (역할 미주입)${NC}"
        role_file=""
    fi
    echo -n "  Pane $i (${M_NAME[$i]} · ${M_ENGINE[$i]} ${M_MODEL[$i]} · ${M_EFFORT[$i]}): "
    start_member_in_pane "$pane_id" "$i" "$role_file" || true

    tmux capture-pane -t "$pane_id" -p 2>/dev/null | grep -q "$(ready_pattern "${M_ENGINE[$i]}")" \
        && echo -e "${GREEN}✅ 준비 완료${NC}" \
        || echo -e "${RED}⚠️  타임아웃 — 수동 확인 필요${NC}"
    i=$((i + 1))
done

# ── [4/4] 완료 ──────────────────────────────────────────────
echo -e "\n${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   ✅ 팀 환경 구성 완료!              ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# 터미널에서 직접 실행한 경우 자동 attach
[ -t 1 ] && tmux attach -t "$SESSION"
