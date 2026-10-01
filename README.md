# claude-ecg-team

tmux + Claude Code 로 다중 페르소나(역할별 페인)를 자동 구성하는 팀 셋업 도구입니다.
한 터미널에 7개 역할의 Claude 인스턴스를 동시에 띄우고, 페인 간에 메시지를 주고받으며
실제 팀처럼 협업할 수 있습니다.

현재 구성은 **백엔드 서비스 개발**(Go 모노레포 기준 브랜치 컨벤션)에 맞춰져 있으며,
Jira Sub-task · 브랜치 전략 · PR 머지 게이트(보안·커버리지·성능·아키텍처) 를 갖춘
**품질 게이트 중심 개발 프로세스**를 따릅니다.

## 의존성

- `tmux`
- `claude` CLI (`@anthropic-ai/claude-code`) — `members.conf` 에 claude 엔진 멤버가 있을 때
- `codex` CLI (`@openai/codex`, 로그인 필요) — `members.conf` 에 codex 엔진 멤버가 있을 때
- `jq` (선택 — team-send-verify Hook 동작에 필요. 미설치 시 Hook 만 graceful skip)
- `rsync` (선택 — 스킬 배포에 사용. 미설치 시 `cp -R` fallback)

## 사용법

```bash
bash setup-team.sh [세션이름] [-d <작업디렉터리>] [-c <멤버설정파일>]
```

- `세션이름` 기본값은 `team`
- `-d` 미지정 시 현재 디렉터리를 작업 디렉터리로 사용 (없으면 생성)
- `-c` 미지정 시 저장소의 `members.conf` 사용 (프로젝트별 팀 구성은 별도 파일로)
- 같은 이름의 세션이 있으면 재생성 여부를 묻고, 거절 시 기존 세션에 attach
- 터미널에서 직접 실행하면 구성 완료 후 자동 attach. 수동 진입은 `tmux attach -t <세션이름>`

### 전역 실행 설정 (선택)

어느 디렉터리에서든 실행하려면 `~/.zshrc` 에 추가합니다.

```zsh
export CLAUDE_ECG_TEAM_HOME="$HOME/MyProject/claude-ecg-team"
export PATH="$CLAUDE_ECG_TEAM_HOME/bin:$PATH"
setup-team() { bash "$CLAUDE_ECG_TEAM_HOME/setup-team.sh" "$@"; }
```

> 심볼릭 링크는 쓰지 마세요. `setup-team.sh` 는 `$(dirname "$0")` 로 `roles/`·`bin/` 위치를
> 찾으므로 링크 경로 기준으로 해석되어 깨집니다. 함수/alias 로 절대 경로를 호출합니다.

```bash
cd ~/work/my-service && setup-team          # 현재 디렉터리를 작업 디렉터리로
setup-team api -d ~/work/api                # 세션 이름·작업 디렉터리 지정
```

## 디렉터리 구조

```
.
├── setup-team.sh           # tmux 멀티페인 자동 셋업 (메인)
├── members.conf            # 멤버 설정 단일 소스 (이름·역할 파일·라벨·모델·effort·별칭)
├── lib/
│   └── members.sh          # members.conf 로더 (setup-team.sh·team-send 공용)
├── bin/
│   ├── team-send           # 페인 간 메시지 전송 헬퍼
│   ├── team-status         # 페인 상태·컨텍스트 사용률 확인 헬퍼
│   └── team-send-verify.sh # team-send 후 수신 페인 활성 검증 (PostToolUse Hook)
├── roles/
│   ├── _team-workflow.md   # 모든 페르소나 공통 워크플로 (역할 파일보다 우선)
│   ├── 제임스.md            # 페르소나별 역할 정의
│   ├── 네이선.md
│   ├── 수진.md
│   ├── 마크저커버그.md
│   ├── 정민.md
│   ├── 수영.md
│   └── 카맥.md
├── skills/
│   └── team-send-verify/   # ~/.claude/skills/ 로 배포되는 Hook 가이드 스킬
├── templates/              # 멤버가 대상 프로젝트 docs/ 를 처음 만들 때 따르는 문서 템플릿
└── docs/
    ├── decisions/          # 이 저장소 자체의 ADR
    └── qa/reviews/         # 이 저장소 자체의 QA 리뷰·회귀 시나리오
```

## 페르소나

| 멤버 | 이름 | 역할 | 핵심 책임 | 엔진 · 모델 · effort |
|---|---|---|---|---|
| 0 | 제임스 | CTO · 오케스트레이터 | 요청 5종 분류 → 위임, 의사결정·트레이드오프, 릴리스(main 머지) 사인오프. 실작업은 직접 하지 않음 | Claude Opus 5.5 · high |
| 1 | 네이선 | 시스템 아키텍트 | 모듈 경계·데이터 흐름 설계, ADR, 마크용 구현 가이드, `interface-change` PR 정합성 리뷰, 현행 아키텍처 역공학 | Claude Opus 5.5 · xhigh |
| 2 | 수진 | 리서처 | 라이브러리·기술 옵션 비교표, 출처(URL·버전) 기반 권장안, 코드 인벤토리·의존성 감사 | Claude Sonnet 5.5 (1M) · medium |
| 3 | 마크(저커버그) | 시니어 개발자 | TDD(RED→GREEN→IMPROVE) 구현, 단위·통합 테스트 작성, 작은 커밋·PR, CI 그린 유지 | Claude Opus 5.5 · xhigh |
| 4 | 정민 | QA · 코드 리뷰어 | 머지 전 마지막 게이트: 보안(OWASP)·정확성·patch 커버리지 80%, E2E·회귀 테스트, 버그 트리아지 | **Codex** gpt-6.1-sol · xhigh |
| 5 | 수영 | UI/UX 디자이너 | 디자인 토큰, 접근성(WCAG 2.2), 반응형·다크모드·reduced-motion, 비주얼 회귀, UI 인벤토리 | Claude Sonnet 5.5 (1M) · medium |
| 6 | 카맥 | 성능·신뢰성 엔지니어 | "측정 없이 추측 금지": N≥5 베이스라인, p50/p95/p99, 부하 테스트, SLI/SLO, perf 예산 게이트 | **Codex** gpt-6.1-sol · medium |

엔진·모델·effort 는 `members.conf` 에서 바꿉니다 (2026-10-01 기준).

- **만드는 쪽은 Claude, 검증하는 쪽은 Codex.** 정민(리뷰 게이트)·카맥(성능 게이트)은 Codex 로 두어
  다른 모델이 검증하게 합니다. 같은 모델끼리 같은 실수를 놓치는 위험을 줄이기 위함입니다.

- 의사결정·설계·구현·머지 게이트처럼 영향이 큰 역할 → `claude-opus-5-5`
- 조사·측정처럼 반복이 많고 컨텍스트가 큰 역할 → `claude-sonnet-5-5[1m]`
- `claude-fable-5-1` 은 기본 배정하지 않습니다. Opus 5.5 의 2.5배 가격이고 한 턴이 길어 페인 간
  협업이 느려집니다. 대규모 설계 등 필요할 때만 해당 페인에서 `/model fable` 로 전환하세요.
- effort 는 `--effort` 로 전달됩니다. 페인 안에서 `/effort` 로 세션 단위 조정도 가능합니다.

세부 역할 정의는 `roles/<이름>.md`, 공통 규칙은 `roles/_team-workflow.md` 를 참조하세요.
실행 시 두 파일이 합쳐져 `--append-system-prompt-file` 로 각 페인에 주입됩니다.

### 협업 흐름 요약

| 요청 유형 | 흐름 |
|---|---|
| 신규 기능·대규모 변경 | 제임스 → 네이선(ADR·구현 가이드) → 마크(TDD 구현·PR) → 정민·카맥(+`interface-change` 시 네이선) 병렬 리뷰 → 머지 |
| 버그 | 제임스 → 정민(재현·심각도·Jira Sub-task) → 마크(재현 절차를 RED 테스트로 수정) → 정민 리뷰 |
| 종합 분석·진단 | 제임스가 5명 분담(분석 모드, 코드 변경 없음) → `docs/analysis/*` 산출 → 제임스 통합 |
| 기술 선택 | 수진(비교표·권장안) → 네이선/제임스 결정 |
| 릴리스 | 정민·카맥 검증 통과 → 제임스 사인오프 → `main` 머지 |

모든 지시는 **1차 자가 검증 → 2차 도메인 멤버 검증** 을 거친 뒤 집행합니다
(`_team-workflow.md` 팀 품질 원칙 4).

## 페인 간 통신

```bash
# 다른 페인에게 메시지 보내기 (한국명 또는 영문 alias)
team-send 정민 "PR #12 리뷰 요청"
team-send qa -f review-request.md
echo "베이스라인 측정 부탁" | team-send perf

# 모든 페인 상태·컨텍스트 사용률 확인
team-status --tail 2
team-status --watch 10        # 10초마다 갱신
team-status --limits          # Codex 사용 한도(5시간·주간)만 확인
```

`setup-team.sh` 가 각 페인의 PATH 에 `bin/` 을 추가하므로 페인 내부에서는 `team-send`,
`team-status` 를 그대로 호출할 수 있습니다. 페인 밖에서 쓰려면 위의 전역 실행 설정을 하세요.

## 커스터마이징

### 멤버 설정 (`members.conf`)

멤버 구성은 `members.conf` 한 파일이 단일 소스입니다. `setup-team.sh` 는 이 파일로 페인 레이아웃·라벨·
모델·effort·역할 주입을 만들고, `team-send` 는 같은 파일로 수신자 이름·별칭을 페인 인덱스로 바꿉니다.

```
# 이름 | 역할파일 | 페인 라벨 | 엔진 | 모델 | effort | 별칭(공백 구분)
제임스 | 제임스       | 제임스 CTO             | claude | claude-opus-5-5 | high  | james cto
정민   | 정민         | 정민 QA·Reviewer       | codex  | gpt-6.1-sol     | xhigh | jungmin qa reviewer
```

- **행 순서 = 멤버 번호.**
- **`[창이름]` 줄로 tmux 창을 나눕니다.** 구획 아래 멤버들이 그 창에 들어가고, 구획이 없으면 창 `team` 하나입니다.
  같은 창 이름을 두 번 쓸 수 없습니다(창의 멤버는 연속으로 적습니다).
- 창마다 첫 멤버는 좌측 메인 페인, 나머지는 우측 2열 그리드에 행 우선으로 배치됩니다.
  우측 인원이 홀수면 마지막 행은 1칸이 전체 폭을 씁니다.
- 세션은 첫 창을 띄운 채 열립니다. 창 이동은 `prefix` + 창 번호, 또는 `prefix n`/`prefix p` 입니다.
  `team-send` 는 창과 무관하게 이름으로 보내고, `team-status` 는 멤버마다 창 이름을 함께 표시합니다.

```
[기획]
제임스   | 제임스   | 제임스 진행         | claude | claude-opus-5-5 | high  | james
블룸     | 블룸     | 블룸 교육리서치     | codex  | gpt-6.1-sol     | xhigh | bloom

[개발]
네이선   | 네이선   | 네이선 Architect    | claude | claude-opus-5-5 | xhigh | nathan
```
- 역할 파일은 `roles/<역할파일>.md`. 없으면 경고 후 역할 없이 기동합니다.
- 형식 오류·중복 이름/라벨·잘못된 엔진(claude/codex)·effort(low~max) 는 tmux 세션을 만들기 전에 중단됩니다.
- `setup-team.sh` 는 사용한 설정 파일 경로를 tmux 세션 옵션 `@team_members_file` 에 기록하고,
  `team-send` 는 이를 먼저 읽습니다(없으면 `TEAM_MEMBERS_FILE` → 기본 `members.conf`).
  그래서 `-c` 로 띄운 세션에서도 `team-send` 가 같은 구성을 씁니다.
- 각 페인에는 멤버 번호 태그 `@member` 가 붙고, `team-send`·`team-status` 는 tmux 인덱스가 아니라 이 태그로
  페인을 찾습니다. 그래서 `~/.tmux.conf` 의 `base-index`·`pane-base-index` 설정과 무관하게 동작합니다.
- 멤버 기동 전에 멤버마다 태그 페인이 하나이고 `@role` 라벨이 일치하는지 검증하고, 불일치 시 세션을 종료합니다.

### Codex 엔진

- 역할 지시는 `-c developer_instructions` 로 주입합니다(공통 워크플로 + 역할 파일, ~45KB). 긴 지시를 페인에
  타이핑하지 않도록 `roles/.merged/<역할파일>.codex.sh` 실행 스크립트를 만들어 호출합니다.
- 실행 옵션은 Claude 의 `--dangerously-skip-permissions` 에 대응하는 `--dangerously-bypass-approvals-and-sandbox` 입니다.
  샌드박스가 꺼져 있어야 Codex 멤버가 `team-send`(tmux)를 쓸 수 있습니다.
- 처음 쓰는 폴더의 신뢰 대화상자는 자동으로 수락합니다. `~/.codex/hooks.json` 의 훅 검토 대화상자는 **신뢰하지 않고 건너뜁니다**
  (해당 실행에서 훅 미적용). 훅을 쓰려면 `codex` 를 한 번 직접 실행해 신뢰를 결정하세요.
- `team-status` 는 Codex 멤버의 컨텍스트를 **남은 비율(left)** 로, 계정 사용 한도(5시간·주간)를 별도 줄로 표시합니다.
  값은 Codex 세션 기록(`~/.codex/sessions/**/rollout-*.jsonl`)에서 읽어 `/status` 와 같으며, 페인에 아무것도 입력하지 않습니다.
  `team-status --limits` 는 한도만 한 줄로 출력합니다. `jq`·`lsof` 가 필요합니다.
- `team-send` 는 Codex 수신자의 5시간 한도가 30% 미만이면 발신자에게 경고합니다(전송은 진행).
  운영 규칙은 `roles/_team-workflow.md` §0.5.1 을 따릅니다.

### 멤버 추가 절차

1. `roles/<역할파일>.md` 작성 (기존 역할 파일 구조 참고: 정체성·책임 범위·워크플로·분석 모드·Do/Don't)
2. `members.conf` 에 한 줄 추가
3. 역할 문서의 협업 관계 갱신 — 설정 파일로는 자동화되지 않는 부분입니다.
   - `roles/_team-workflow.md` §8.1 페인 매핑 표, 위임·검증 담당 언급
   - `roles/제임스.md` 위임 대상 목록, 도메인별 2차 검증 담당
   - 새 멤버와 인계·리뷰 관계가 생기는 멤버의 역할 파일

인원이 늘면 페인이 작아지므로 터미널을 크게 두세요(최소 높이는 행당 14줄로 자동 보강).

### 프로젝트 특화

- `roles/_team-workflow.md` 의 `decg-link`, `TECG-123`, `v1.0.0.0` 등은 **예시 값**입니다.
  실제 product 명·Jira 키·브랜치 컨벤션은 대상 프로젝트의 `CLAUDE.md` 또는 메모리(`project-*`)에 두고,
  공통 워크플로는 범용으로 유지하는 것을 권장합니다.
- 역할 파일의 Redis 세션 저장소·TypeScript 코드 블록은 ADR·구현 가이드 **작성 예시**이며 기술 스택 지정이 아닙니다.
- 프로젝트마다 인원·모델이 다르면 `members.conf` 를 복사해 수정하고 `setup-team -c <파일>` 로 띄웁니다.
- 프런트엔드 비중이 큰 프로젝트라면 수영을 `claude-opus-5-5` · `high` 이상으로 올리세요.
- 문서 템플릿(`templates/`)을 프로젝트 양식에 맞게 수정하면 멤버가 생성하는 `docs/` 산출물 형식이 바뀝니다.

## 빌드 산출물

`roles/.merged/` 는 `setup-team.sh` 가 공통 워크플로와 역할 파일을 합쳐서 만드는
런타임 합성 결과물입니다. 매 실행마다 새로 생성되므로 절대 커밋하지 않습니다
(`.gitignore` 처리됨).

## team-send-verify Hook (자동 배포)

`setup-team.sh` 실행 시 다음 두 가지가 사용자 전역 (`~/.claude/`) 으로 자동 배포됩니다.

- `bin/team-send-verify.sh` 를 가리키는 **PostToolUse Hook** — `~/.claude/settings.json` 에 jq smart merge 로 등록
- `skills/team-send-verify/SKILL.md` → `~/.claude/skills/team-send-verify/` 로 rsync

### 동작

`team-send` 호출 직후 자동 발동:

1. 수신자 페인을 capture 해 활성 상태 확인 (단일 패턴 `\(([0-9]+m )?[0-9]+s · [↑↓]` — 처리 중 토큰 카운터 footer 괄호 매칭. 분 포맷 자동 지원. Crunched 같은 완료 메시지는 괄호 부재 → 자동 차단)
2. 미활성 시 자동으로 Enter 보강 송신
3. 여전히 미활성이면 stderr 진단 가이드 + exit 2 (사용자에게 안내)

**Esc 자동 발사 등 destructive 동작은 절대 수행 안 함** — 페인 사용자 작업 보호.

상세 가이드: `skills/team-send-verify/SKILL.md` (배포 후 `~/.claude/skills/team-send-verify/SKILL.md`).

### 해제 방법

본 Hook 비활성화가 필요한 경우 (fork 사용자 / 다른 PostToolUse Hook 와 충돌 / 디버그):

```bash
# 1. 임시 비활성화 — file watcher 가 즉시 픽업
jq 'del(.hooks.PostToolUse[]?.hooks[]? | select(.command | endswith("team-send-verify.sh")))' \
    ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json

# 2. 영구 비활성화 — ~/.claude/settings.json 직접 편집해서 PostToolUse 배열에서 entry 제거
$EDITOR ~/.claude/settings.json

# 3. 재활성화 — setup-team.sh 재실행 (idempotent jq merge 로 안전)
bash setup-team.sh
```

### 의존성

- `jq` — 미설치 시 setup-team.sh 가 warning 만 표시하고 Hook 등록은 skip. Hook 자체는 graceful exit (warning + skip). 다른 단계는 정상 진행.
- 로그: `/tmp/team-send-verify.log` (tail -20 으로 최근 이력 확인)

### 근거 문서

- ADR: `docs/decisions/2026-06-09-team-send-verify-hook.md`
- 회귀 시나리오: `docs/qa/reviews/team-send-verify-test-scenarios-2026-06-09.md`
- 공통 워크플로: `roles/_team-workflow.md` §8.2.1 / §8.2.2 / §8.4.x
