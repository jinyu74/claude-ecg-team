# members.sh — members.conf 로더 (setup-team.sh · bin/team-send 가 source)
# bash 3.2 호환 (macOS 기본 bash): 연관 배열·mapfile 미사용.
#
# load_members <file>
#   성공 시 아래 배열을 채운다 (인덱스 = tmux 페인 인덱스).
#   M_NAME M_ROLE M_LABEL M_MODEL M_EFFORT M_ALIASES, M_COUNT
#   실패 시 stderr 에 사유를 출력하고 1 반환.

_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

load_members() {
    local file="$1" line lineno=0 name role label model effort aliases extra i
    M_NAME=(); M_ROLE=(); M_LABEL=(); M_MODEL=(); M_EFFORT=(); M_ALIASES=(); M_COUNT=0

    [ -f "$file" ] || { echo "멤버 설정 파일 없음: $file" >&2; return 1; }

    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="$(_trim "$line")"
        case "$line" in ''|'#'*) continue ;; esac

        IFS='|' read -r name role label model effort aliases extra <<EOF
$line
EOF
        name="$(_trim "$name")"; role="$(_trim "$role")"; label="$(_trim "$label")"
        model="$(_trim "$model")"; effort="$(_trim "$effort")"; aliases="$(_trim "$aliases")"

        if [ -n "$extra" ] || [ -z "$name" ] || [ -z "$label" ] || [ -z "$model" ] || [ -z "$effort" ]; then
            echo "$file:$lineno: 형식 오류 — '이름 | 역할파일 | 페인 라벨 | 모델 | effort | 별칭'" >&2
            return 1
        fi
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

        M_NAME[$M_COUNT]="$name"; M_ROLE[$M_COUNT]="${role:-$name}"; M_LABEL[$M_COUNT]="$label"
        M_MODEL[$M_COUNT]="$model"; M_EFFORT[$M_COUNT]="$effort"; M_ALIASES[$M_COUNT]="$aliases"
        M_COUNT=$((M_COUNT + 1))
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
