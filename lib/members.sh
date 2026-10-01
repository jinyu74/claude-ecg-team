# members.sh — members.conf 로더 (setup-team.sh · bin/team-send 가 source)
# bash 3.2 호환 (macOS 기본 bash): 연관 배열·mapfile 미사용.
#
# load_members <file>
#   성공 시 아래 배열을 채운다 (인덱스 = tmux 페인 인덱스).
#   M_NAME M_ROLE M_LABEL M_ENGINE M_MODEL M_EFFORT M_ALIASES M_WINDOW, M_COUNT
#   W_NAME (창 이름, 등장 순서), W_COUNT
#
# '[창이름]' 줄은 이후 멤버를 그 tmux 창에 배치한다. 첫 구획 이전 멤버는 창 'team'.
#   실패 시 stderr 에 사유를 출력하고 1 반환.

_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

load_members() {
    local file="$1" line lineno=0 name role label engine model effort aliases extra i window="team" w
    M_NAME=(); M_ROLE=(); M_LABEL=(); M_ENGINE=(); M_MODEL=(); M_EFFORT=(); M_ALIASES=(); M_WINDOW=(); M_COUNT=0
    W_NAME=(); W_COUNT=0

    [ -f "$file" ] || { echo "멤버 설정 파일 없음: $file" >&2; return 1; }

    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="$(_trim "$line")"
        case "$line" in ''|'#'*) continue ;; esac

        # 창 구획: [창이름]
        case "$line" in
            '['*']')
                window="$(_trim "${line#[}")"; window="$(_trim "${window%]}")"
                [ -n "$window" ] || { echo "$file:$lineno: 빈 창 이름" >&2; return 1; }
                w=0
                while [ $w -lt $W_COUNT ]; do
                    [ "${W_NAME[$w]}" = "$window" ] && { echo "$file:$lineno: 중복 창 '$window'" >&2; return 1; }
                    w=$((w + 1))
                done
                continue ;;
        esac

        IFS='|' read -r name role label engine model effort aliases extra <<EOF
$line
EOF
        name="$(_trim "$name")"; role="$(_trim "$role")"; label="$(_trim "$label")"; engine="$(_trim "$engine")"
        model="$(_trim "$model")"; effort="$(_trim "$effort")"; aliases="$(_trim "$aliases")"

        if [ -n "$extra" ] || [ -z "$name" ] || [ -z "$label" ] || [ -z "$engine" ] || [ -z "$model" ] || [ -z "$effort" ]; then
            echo "$file:$lineno: 형식 오류 — '이름 | 역할파일 | 페인 라벨 | 엔진 | 모델 | effort | 별칭'" >&2
            return 1
        fi
        case "$engine" in
            claude|codex) ;;
            *) echo "$file:$lineno: 잘못된 엔진 '$engine' (claude/codex)" >&2; return 1 ;;
        esac
        # 두 엔진 모두 low~max 를 받는다 (Codex 는 minimal 도 있으나 gpt-6.1-sol 이 거부).
        case "$effort" in
            low|medium|high|xhigh|max) ;;
            *) echo "$file:$lineno: 잘못된 effort '$effort' (low/medium/high/xhigh/max)" >&2; return 1 ;;
        esac
        i=0
        while [ $i -lt $M_COUNT ]; do
            [ "${M_NAME[$i]}" = "$name" ] && { echo "$file:$lineno: 중복 이름 '$name'" >&2; return 1; }
            [ "${M_LABEL[$i]}" = "$label" ] && { echo "$file:$lineno: 중복 페인 라벨 '$label'" >&2; return 1; }
            i=$((i + 1))
        done

        M_NAME[$M_COUNT]="$name"; M_ROLE[$M_COUNT]="${role:-$name}"; M_LABEL[$M_COUNT]="$label"; M_ENGINE[$M_COUNT]="$engine"; M_WINDOW[$M_COUNT]="$window"
        M_MODEL[$M_COUNT]="$model"; M_EFFORT[$M_COUNT]="$effort"; M_ALIASES[$M_COUNT]="$aliases"
        M_COUNT=$((M_COUNT + 1))
        # 멤버가 있는 창만 등록 (등장 순서 유지)
        if [ $W_COUNT -eq 0 ] || [ "${W_NAME[$((W_COUNT - 1))]}" != "$window" ]; then
            W_NAME[$W_COUNT]="$window"; W_COUNT=$((W_COUNT + 1))
        fi
    done < "$file"

    [ "$M_COUNT" -gt 0 ] || { echo "$file: 멤버가 없습니다" >&2; return 1; }
}

# member_index <이름|역할파일|별칭> — 페인 인덱스 출력, 없으면 빈 문자열
member_index() {
    local key="$1" i=0 a
    while [ $i -lt $M_COUNT ]; do
        [ "$key" = "${M_NAME[$i]}" ] || [ "$key" = "${M_ROLE[$i]}" ] && { echo $i; return; }
        for a in ${M_ALIASES[$i]}; do
            [ "$key" = "$a" ] && { echo $i; return; }
        done
        i=$((i + 1))
    done
}

# member_pane_id <session> <멤버 인덱스> — 해당 멤버 페인의 pane_id(%N) 출력
# tmux base-index·pane-base-index·창 분리와 무관하도록 인덱스가 아닌 페인 태그(@member)로 찾는다.
member_pane_id() {
    tmux list-panes -s -t "$1" -F '#{@member} #{pane_id}' 2>/dev/null \
        | awk -v i="$2" 'NF == 2 && $1 == i { print $2; exit }'
}
