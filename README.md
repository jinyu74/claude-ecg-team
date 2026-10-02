# claude-ecg-team

tmux + Claude Code + Codex 로 역할별 AI 멤버를 페인마다 띄워 실제 팀처럼 협업하게 하는 팀 셋업 도구입니다.
멤버는 페인 간 메시지(`team-send`)로 일을 주고받고, `team-status` 로 상태·컨텍스트·Codex 사용 한도를 확인합니다.

- **모든 결정은 사용자가 합니다.** 제임스는 결정하지 않는 진행자로, 쟁점을 세우고 토론을 진행해 결정 요청서를 올립니다.
- **서로 다른 모델이 토론·검증합니다.** 기획은 Claude·Codex 결정 페어가 각자 안을 내고 비판해 선택지를 정리하고,
  개발은 Claude 가 만들고 Codex 가 검증합니다.
- **새 프로젝트는 아이디어 팀에서 시작합니다.** 컨셉·프로젝트 유형·팀 구성을 사용자가 정한 뒤 프로젝트 팀을 띄웁니다.

## 빠른 시작

```bash
# 1. 아이디어 팀 띄우기 (-c 생략 = 아이디어 팀)
setup-team ideas -d ~/MyProject/ideas

# 2. 접속해서 제임스(왼쪽 큰 페인)에게 주제를 준다
tmux attach -t ideas

# 3. 컨셉·팀 구성이 결정되면 프로젝트 팀 띄우기
setup-team edu -d ~/MyProject/edu-game -c edu-game
```

tmux 조작(창·페인 이동, 스크롤, 빠져나오기)은 **[tmux 사용 가이드](docs/guides/tmux-guide.md)** 를 참고하세요.

## 설치

### 의존성

- `tmux`
- `claude` CLI (`@anthropic-ai/claude-code`) — 팀에 Claude 멤버가 있을 때
- `codex` CLI (`@openai/codex`, 로그인 필요) — 팀에 Codex 멤버가 있을 때
- `jq` — Codex 컨텍스트·한도 조회, team-send-verify Hook 등록 (없으면 해당 기능만 건너뜀)
- `lsof` — Codex 페인과 세션 기록 연결 (macOS 기본 포함)
- `rsync` (선택) — 스킬 배포. 없으면 `cp -R`

### 전역 실행 설정

어느 디렉터리에서든 실행하려면 `~/.zshrc` 에 추가합니다.

```zsh
export CLAUDE_ECG_TEAM_HOME="$HOME/MyProject/claude-ecg-team"
export PATH="$CLAUDE_ECG_TEAM_HOME/bin:$PATH"
setup-team() { bash "$CLAUDE_ECG_TEAM_HOME/setup-team.sh" "$@"; }
```

> 심볼릭 링크는 쓰지 마세요. `setup-team.sh` 는 `$(dirname "$0")` 로 `roles/`·`bin/`·`teams/` 를 찾으므로
> 링크 경로 기준으로 해석되어 깨집니다. 함수로 절대 경로를 호출합니다.

## 사용법

```bash
setup-team [세션이름] [-d <작업디렉터리>] [-c <팀 이름|설정 파일>]
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `세션이름` | `team` | tmux 세션 이름. 팀마다 다르게 지으면 여러 팀을 동시에 띄울 수 있다 |
| `-d` | 현재 디렉터리 | 멤버들이 문서·코드를 만들 작업 폴더 (없으면 생성) |
| `-c` | `idea` | 팀 이름(`teams/<이름>.conf`) 또는 설정 파일 경로. `setup-team -h` 에 팀 목록 표시 |

- 같은 이름의 세션이 있으면 재생성 여부를 묻고, 거절하면 기존 세션에 접속합니다.
- 터미널에서 직접 실행하면 구성 완료 후 자동 접속합니다. 직접 접속은 `tmux attach -t <세션이름>`.
- 역할 파일·팀 설정 변경은 **세션을 새로 띄울 때** 반영됩니다(멤버는 지시를 시작 시 한 번 읽음).

## 조직

### 원칙

| 원칙 | 내용 | 근거 |
|---|---|---|
| 결정권 | 사용자 한 명. 제임스는 진행자 — 쟁점 정의, 토론 진행, 결정 요청서 상정, 결정 기록·인계 | 공통 워크플로 "결정 권한" |
| 결정 페어 | 기획 역할은 Claude 1 + Codex 1 이 같은 역할 파일을 쓰고 관점만 다르게. 독립 초안 → 상호 비판 ≤2라운드 → 결정 요청서 | §10 |
| 교차 검증 | 개발은 만드는 쪽 Claude, 검증하는 쪽 Codex (정민·카맥) | §11 |
| 디렉터 위임 | 내러티브 팀의 우에다는 사용자가 위임한 작은 창작 판단(대사 다듬기·장면 연출 세부·음악 큐 위치)을 판단·기록 | §13 |
| 아이디어 → 프로젝트 | 새 프로젝트는 아이디어 팀에서 컨셉·유형·팀 구성을 정한 뒤 프로젝트 팀으로 | §14 |

공통 워크플로는 `roles/_team-workflow.md` 이고 역할 파일보다 우선합니다.

### 팀 목록 (`teams/`)

| 팀 | 설정 | 인원 (Claude : Codex) | 창 | 용도 |
|---|---|---|---|---|
| 아이디어 팀 | `idea` (기본) | 10 (5 : 5) | 아이디어 | 초기 리서치·컨셉 발산·수렴, 프로젝트 팀 구성안 |
| 학습 게임 팀 | `edu-game` | 15 (10 : 5) | 기획 · 개발 | 재미있고 교육적인 게임 |
| 내러티브 게임 팀 | `narrative` | 14 (10 : 4) | 기획 · 개발 | 영화 같은 시나리오, 주인공 몰입, 엔딩의 감동 |
| 백엔드 팀 | `backend` | 7 (5 : 2) | team | 개편 전 구성 (백엔드 서비스) |

형식과 모델·effort 배정 원칙은 [`teams/README.md`](teams/README.md) 에 있습니다.

### 아이디어 팀

| 관점 | Claude | Codex |
|---|---|---|
| 진행 | 제임스 | |
| 컨셉 (결정 페어) | 미야모토 | 라이트 |
| 교육 | 비고츠키 | 블룸 |
| 서사 | 닥터 | 드럭만 |
| 조사 · 규모 추정 | | 수진 · 네이선 |
| 비주얼 컨셉 | 수영 | |

주제 정의 → 독립 발산 → 관점별 검증 → 컨셉 결정 요청(**사용자: 컨셉·프로젝트 유형 결정**) →
팀 구성안 `teams/<프로젝트>.conf` 초안(**사용자: 팀 구성 결정**) → 프로젝트 팀으로 인계.

### 학습 게임 팀

**기획 창**

| 이름 | 역할 | 엔진 · effort | 관점·책임 |
|---|---|---|---|
| 제임스 | 진행자 | Claude Opus · high | 쟁점 정의, 토론 진행, 결정 요청서 상정, 상시 모니터링 |
| 비고츠키 · 블룸 | 교육 리서치 | Claude Opus · high / Codex · medium | 비계·사회적 학습 / 측정 가능한 목표·평가 |
| 파인만 · 세이건 | 콘텐츠 기획 | Claude Opus · high / Codex · medium | 개념의 본질·직관 / 경이감·이야기 |
| 미야모토 · 라이트 | 게임 기획 | Claude Opus · high / Codex · medium | 손맛·코어 루프 / 시스템·주도성 |

**개발 창**

| 이름 | 역할 | 엔진 · effort | 핵심 책임 |
|---|---|---|---|
| 네이선 | 아키텍트 | Claude Opus · xhigh | ADR, 데이터 모델, 클라이언트·서버 경계, 구현 가이드 |
| 마크 | 백엔드 | Claude Opus · xhigh | 서버·API, 콘텐츠 처리 도구, 이벤트 수집, TDD |
| 이와타 | 클라이언트 | Claude Opus · xhigh | 게임·앱 화면, 조작, 오프라인, 크로스플랫폼 배포, TDD |
| 정민 | QA · 리뷰 게이트 | **Codex** · high | 보안·품질·커버리지, 아동 개인정보·스토어 정책·다크패턴, ADR 반론 |
| 카맥 | 성능 게이트 | **Codex** · medium | 저사양 기기 기준 프레임·로딩·용량·배터리, ADR 반론 |
| 수진 | 리서처 | Claude Sonnet (1M) · medium | 엔진·기술 비교, 경쟁작·시장, 플랫폼 정책 |
| 수영 | 디자인 리드 | Claude Opus · high | UI/UX, 아트 방향·스타일 가이드, 접근성 |
| 히사이시 | 음악 감독 · 에셋 | Claude Sonnet (1M) · medium | 테마 선율·음악 큐, 에셋 명세·조달·라이선스 (외부 도구는 매번 최신 조사) |

### 내러티브 게임 팀

기획 창은 교육 리서치·콘텐츠 기획 페어 대신 아래 멤버로 구성되고(제임스·미야모토·라이트 포함), 개발 창은 학습 게임 팀과 같습니다.

| 이름 | 역할 | 엔진 · effort | 관점·책임 |
|---|---|---|---|
| 우에다 | 디렉터 | Claude Opus · high | 톤 바이블·감정 지도·연출 방향·일관성 검수, 위임된 작은 창작 판단 (`docs/direction/delegated-log.md` 에 기록) |
| 닥터 · 드럭만 | 시나리오 기획 | Claude Opus · high / Codex · medium | 인물·감정 중심 / 구조·긴장 중심 |

줄거리·결말·인물의 운명·분기 구조·톤 바이블은 사용자가 결정합니다.

### 모델 배정

- Claude Opus 5.5 — 진행·기획 판단·설계·구현·디자인 리드 / Claude Sonnet 5.5 (1M) — 조사·에셋
- Codex gpt-6.1-sol — 결정 페어의 다른 관점, 검증 게이트, 아이디어 팀의 조사·규모 추정
- Fable 5.1 은 기본 배정하지 않습니다(필요 시 페인에서 `/model fable`).
- **Codex 멤버는 계정 사용 한도를 공유합니다.** 여러 팀을 동시에 띄우면 함께 씁니다. `team-status --limits` 로 확인하고,
  한도가 부족하면 제임스가 선택지(대기 / Claude 쪽 임시 재배정 / effort 하향)를 올립니다(§0.5.1).

### 협업 흐름

| 요청 | 흐름 |
|---|---|
| 새 프로젝트 | 아이디어 팀: 발산 → 검증 → 컨셉 결정 요청 → **사용자 결정** → 팀 구성안 → **사용자 결정** → 프로젝트 팀 (§14) |
| 기획 쟁점 | 제임스 쟁점 정의 → 해당 페어 독립 초안 → 상호 비판(≤2라운드) → 결정 요청서 → **사용자 결정** → 개발 인계 (§10·§12) |
| 장면 안 창작 판단 (내러티브) | 우에다가 판단·기록, 사용자는 언제든 뒤집을 수 있음 (§13) |
| 기술 선택 | 수진 조사 → 네이선 ADR 초안 → 정민·카맥 반론 → 제임스 상정 → **사용자 결정** (§11) |
| 구현 | 네이선 구현 가이드 → 마크·이와타 TDD·PR → 정민·카맥(+`interface-change` 시 네이선) 병렬 게이트 → 머지 (§7.1) |
| 버그 | 제임스 → 정민 트리아지 → 마크·이와타 수정 → 정민 리뷰 (§3.10) |
| 외부 도구 | 히사이시·수진 최신 조사(출처·확인일·상업/아동 이용 조건) → 제임스 상정 → **사용자 결정** |
| 릴리스 | 정민·카맥 검증 통과 → 제임스 상정 → **사용자 승인** → `main` 머지 |

모든 지시는 **1차 자가 검증 → 2차 도메인 멤버 검증**을 거친 뒤 집행합니다(공통 워크플로 품질 원칙 4).

## 멤버와 소통

```bash
team-send 정민 "PR #12 리뷰 요청"          # 이름 또는 별칭(qa 등)으로 전송
team-send qa -f review-request.md          # 파일 내용 전송
echo "베이스라인 측정 부탁" | team-send perf
team-send -h                               # 현재 세션의 멤버 이름·별칭

team-status                                # 전 멤버 상태·창·컨텍스트 + Codex 한도
team-status --tail 3                       # 멤버별 마지막 3줄
team-status --watch 10                     # 10초마다 갱신
team-status --limits                       # Codex 5시간·주간 한도만
```

- `team-send` 는 창이 달라도 이름으로 보냅니다. 수신자 입력창에 메시지가 남으면 Enter 를 다시 보내고,
  Codex 수신자의 5시간 한도가 30% 미만이면 경고합니다.
- `team-status` 의 컨텍스트는 Claude 는 사용률(used), Codex 는 남은 비율(left)입니다. Codex 값은 세션 기록에서 읽어
  `/status` 와 같으며 페인에 아무것도 입력하지 않습니다.
- 페인 안에서는 `bin/` 이 PATH 에 들어가 있어 바로 쓸 수 있습니다. 페인 밖에서 쓰려면 전역 실행 설정을 하세요.

## 동작 방식

### 실행 시 주입되는 지시

각 멤버에게 다음 세 가지가 합쳐져 주입됩니다. 파일은 `roles/.merged/<세션>/<이름>.md` 에 생성되며(세션별 폴더라 여러 팀을 동시에 띄워도 섞이지 않음), 커밋하지 않습니다(`.gitignore`).

1. **정체 블록** — 이름·별칭, 엔진·모델·effort, 프로젝트(`@project`), 창, 같은 역할의 페어 상대
2. **공통 워크플로** — `roles/_team-workflow.md`
3. **역할 파일** — `roles/<역할파일>.md`. 프로젝트 유형별 항목은 정체 블록의 프로젝트에 해당할 때만 적용

Claude 는 `--append-system-prompt-file`, Codex 는 `-c developer_instructions` 로 주입합니다.

### 페인 찾기

- 각 페인에 멤버 번호(`@member`)·라벨(`@role`)·엔진(`@engine`) 태그를 붙이고, `team-send`·`team-status` 는 tmux 번호가 아니라
  이 태그로 페인을 찾습니다. `~/.tmux.conf` 의 `base-index` 설정과 무관합니다.
- 사용한 팀 설정 경로는 세션 옵션 `@team_members_file` 에 기록되어, `team-send` 가 그 세션의 구성을 씁니다.
- 멤버 기동 전에 태그 매핑을 검증하고, 어긋나면 세션을 종료합니다.

### Codex 멤버

- 실행 옵션: `--dangerously-bypass-approvals-and-sandbox`(Claude 의 `--dangerously-skip-permissions` 대응 — 샌드박스가 꺼져 있어야
  `team-send` 로 tmux 를 쓸 수 있음), `--search`(웹 검색), `-c check_for_update_on_startup=false`.
- 기동 시 업데이트 확인을 끄는 이유: 업데이트 안내가 뜬 상태에서 자동 입력된 Enter 가 "Update now" 로 선택되어 전역 업데이트가
  실행된 적이 있습니다. Codex 업데이트는 직접 하세요(`npm install -g @openai/codex`).
- 처음 쓰는 폴더의 신뢰 대화상자는 자동 수락합니다. `~/.codex/hooks.json` 훅 검토 대화상자는 **신뢰하지 않고 건너뜁니다**
  (그 실행에서 훅 미적용). 훅을 쓰려면 `codex` 를 한 번 직접 실행해 신뢰를 결정하세요.

## 커스터마이징

### 멤버 추가

1. `roles/<역할파일>.md` 작성 — 정체성·책임 범위·워크플로·분석 모드·Do/Don't. 결정 페어라면 한 파일에 "페어 구성"(관점별 표)을 둡니다.
2. 팀 설정 `teams/<팀>.conf` 에 한 줄 추가 (형식: `teams/README.md`).
3. 설정으로 자동화되지 않는 협업 관계를 갱신합니다.
   - `roles/_team-workflow.md` §8.1 멤버 구성 표, 위임·검증 담당 언급
   - `roles/제임스.md` 위임 대상·도메인별 2차 검증 담당
   - 새 멤버와 인계·리뷰 관계가 생기는 역할 파일

인원이 늘면 페인이 작아집니다. 창을 나누거나(`[창이름]`) 터미널을 크게 두세요.

### 새 팀

보통은 아이디어 팀이 가장 가까운 팀 설정을 출발점으로 구성안을 제안합니다(§14). 직접 만들 때는 `teams/*.conf` 를 복사해
수정하고 `@project` 줄로 프로젝트 종류를 적습니다.

### 프로젝트 특화

- 공통 워크플로의 `decg-link`, `TECG-123`, `v1.0.0.0` 등은 **예시 값**입니다. 실제 product 명·Jira 키·브랜치 컨벤션은
  대상 프로젝트의 `CLAUDE.md`(Codex 는 `AGENTS.md`) 또는 메모리에 둡니다.
- 역할 파일의 Redis·TypeScript 코드 블록은 ADR·구현 가이드 **작성 예시**이며 기술 스택 지정이 아닙니다.
- `templates/` 를 수정하면 멤버가 처음 만드는 `docs/` 산출물 형식이 바뀝니다.

## 디렉터리 구조

```
.
├── setup-team.sh            # 팀 세션 구성 (메인)
├── bin/
│   ├── team-send            # 멤버 간 메시지 전송
│   ├── team-status          # 멤버 상태·컨텍스트·Codex 한도
│   └── team-send-verify.sh  # Claude PostToolUse Hook (전송 이력 로그)
├── lib/
│   ├── members.sh           # 팀 설정 로더
│   └── codex.sh             # Codex 컨텍스트·사용 한도 조회
├── teams/                   # 팀 설정 + README (형식·배정 원칙)
├── roles/                   # 공통 워크플로 + 역할 파일
│   ├── _team-workflow.md
│   ├── 제임스.md · 우에다.md
│   ├── 교육리서치.md · 콘텐츠기획.md · 게임기획.md · 시나리오기획.md   # 결정 페어 공용
│   ├── 네이선.md · 마크저커버그.md · 이와타.md · 정민.md · 카맥.md
│   └── 수진.md · 수영.md · 히사이시.md
├── skills/team-send-verify/ # ~/.claude/skills/ 로 배포되는 Hook 가이드
├── templates/               # 멤버가 대상 프로젝트 docs/ 를 처음 만들 때 쓰는 템플릿
└── docs/
    ├── decisions/           # 이 저장소의 ADR
    ├── guides/              # 사용 가이드 (tmux)
    └── qa/reviews/          # 이 저장소의 QA 리뷰·회귀 시나리오
```

## team-send-verify Hook

`setup-team.sh` 실행 시 Claude 사용자 전역(`~/.claude/`)에 자동 배포됩니다.

- `bin/team-send-verify.sh` 를 가리키는 **PostToolUse Hook** — `~/.claude/settings.json` 에 jq 로 병합 등록 (중복 없음, 다른 Hook 보존, 등록 전 백업)
- `skills/team-send-verify/SKILL.md` → `~/.claude/skills/team-send-verify/`

현재 Hook 은 **전송 이력만 기록**합니다(로그 `/tmp/team-send-verify.log`). 전달 확인(입력창 잔존 검사·Enter 재발사)은
2026-07-09 부터 `team-send` 자체가 수행하며, Codex 멤버에게는 이 Hook 이 없습니다.

비활성화:

```bash
jq 'del(.hooks.PostToolUse[]?.hooks[]? | select(.command | endswith("team-send-verify.sh")))' \
    ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json
```

다음 `setup-team` 실행 때 다시 등록됩니다. 영구히 빼려면 `setup-team.sh` 의 Hook 배포 단계를 수정하세요.

근거: `docs/decisions/2026-06-09-team-send-verify-hook.md`, `docs/qa/reviews/team-send-verify-test-scenarios-2026-06-09.md`
