# claude-ecg-team

tmux + Claude Code + Codex 로 다중 페르소나(역할별 페인)를 자동 구성하는 팀 셋업 도구입니다.
한 터미널에 여러 역할의 Claude·Codex 인스턴스를 띄우고, 페인 간에 메시지를 주고받으며
실제 팀처럼 협업할 수 있습니다.

현재 구성(2026-10-02)은 **재미있고 교육적인 게임 앱 개발**을 위한 15명 조직입니다.
기획 파트는 Claude·Codex 결정 페어가 토론해 결정 요청서를 올리고, 개발 파트는 Claude 가 만들고
Codex 가 검증합니다. **모든 결정은 사용자가 합니다.** 개발 프로세스는 Jira Sub-task · 브랜치 전략 ·
PR 머지 게이트(보안·커버리지·성능·아키텍처)를 갖춘 품질 게이트 중심입니다.

## 의존성

- `tmux`
- `claude` CLI (`@anthropic-ai/claude-code`) — 팀 설정에 claude 엔진 멤버가 있을 때
- `codex` CLI (`@openai/codex`, 로그인 필요) — 팀 설정에 codex 엔진 멤버가 있을 때
- `jq` (선택 — team-send-verify Hook 동작에 필요. 미설치 시 Hook 만 graceful skip)
- `rsync` (선택 — 스킬 배포에 사용. 미설치 시 `cp -R` fallback)

## 사용법

```bash
bash setup-team.sh [세션이름] [-d <작업디렉터리>] [-c <팀 이름|설정 파일>]
```

- `세션이름` 기본값은 `team`
- `-d` 미지정 시 현재 디렉터리를 작업 디렉터리로 사용 (없으면 생성)
- `-c` 미지정 시 **아이디어 팀**(`teams/idea.conf`). 팀 이름만 쓰면 `teams/<이름>.conf` (예: `-c edu-game`), 경로도 가능
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
├── lib/
│   └── members.sh          # 팀 설정 로더 (setup-team.sh·team-send 공용)
├── bin/
│   ├── team-send           # 페인 간 메시지 전송 헬퍼
│   ├── team-status         # 페인 상태·컨텍스트 사용률 확인 헬퍼
│   └── team-send-verify.sh # team-send 후 수신 페인 활성 검증 (PostToolUse Hook)
├── roles/
│   ├── _team-workflow.md   # 모든 멤버 공통 워크플로 (역할 파일보다 우선)
│   ├── 제임스.md            # 진행자
│   ├── 교육리서치.md        # 결정 페어 공용 (비고츠키·블룸)
│   ├── 콘텐츠기획.md        # 결정 페어 공용 (파인만·세이건)
│   ├── 게임기획.md          # 결정 페어 공용 (미야모토·라이트)
│   ├── 시나리오기획.md      # 결정 페어 공용 (닥터·드럭만, 내러티브 팀)
│   ├── 우에다.md            # 디렉터 (내러티브 팀)
│   ├── 네이선.md · 마크저커버그.md · 이와타.md
│   ├── 정민.md · 카맥.md
│   └── 수진.md · 수영.md · 히사이시.md
├── teams/                  # 팀 설정 (형식·배정 원칙: teams/README.md)
│   ├── idea.conf           # 아이디어 팀 10명 (기본)
│   ├── edu-game.conf       # 학습 게임 팀 15명
│   ├── narrative.conf      # 내러티브 게임 팀 14명
│   └── backend.conf        # 개편 전 7명 구성
├── skills/
│   └── team-send-verify/   # ~/.claude/skills/ 로 배포되는 Hook 가이드 스킬
├── templates/              # 멤버가 대상 프로젝트 docs/ 를 처음 만들 때 따르는 문서 템플릿
└── docs/
    ├── decisions/          # 이 저장소 자체의 ADR
    └── qa/reviews/         # 이 저장소 자체의 QA 리뷰·회귀 시나리오
```

## 조직 (2026-10-02 개편)

### 시작은 아이디어 팀 (`teams/idea.conf`, 10명 — Claude 5 : Codex 5)

새 프로젝트는 아이디어 팀에서 시작합니다. 컨셉을 발산·검증·수렴해 **사용자가 컨셉과 프로젝트 유형을 결정**하면,
제임스가 프로젝트 팀 구성안(`teams/<프로젝트>.conf`)을 제안하고 **사용자가 팀 구성을 결정**합니다(`roles/_team-workflow.md` §14).

| 관점 | 멤버 (Claude · Codex) |
|---|---|
| 진행 | 제임스 |
| 컨셉 결정 페어 | 미야모토 · 라이트 |
| 교육 | 비고츠키 · 블룸 |
| 서사 | 닥터 · 드럭만 |
| 조사 · 규모 추정 | 수진 · 네이선 (모두 Codex) |
| 비주얼 컨셉 | 수영 |

```bash
setup-team ideas -d ~/MyProject/ideas     # -c 생략 = 아이디어 팀
```

아래는 컨셉 결정 후 띄우는 프로젝트 팀입니다.


**결정은 사용자가 합니다.** 제임스는 결정하지 않는 진행자로, 쟁점을 세우고 토론을 진행해
선택지와 근거를 정리한 결정 요청서를 올립니다. 세션은 tmux 창 두 개로 열립니다.

### 기획 창 — 진행 + 결정 페어

| 이름 | 역할 | 엔진 · 모델 · effort | 관점 |
|---|---|---|---|
| 제임스 | 진행자 | Claude Opus 5.5 · high | 쟁점 정의, 토론 진행, 결정 요청서 상정, 결정 기록·인계, 상시 모니터링 |
| 비고츠키 | 교육 리서치 | Claude Opus 5.5 · high | 근접발달영역·비계·사회적 학습 |
| 블룸 | 교육 리서치 | **Codex** gpt-6.1-sol · medium | 측정 가능한 학습 목표·평가 정합성 |
| 파인만 | 콘텐츠 기획 | Claude Opus 5.5 · high | 개념의 본질·직관적 설명 |
| 세이건 | 콘텐츠 기획 | **Codex** gpt-6.1-sol · medium | 경이감·이야기·맥락 |
| 미야모토 | 게임 기획 | Claude Opus 5.5 · high | 손맛·코어 루프·즉각적인 재미 |
| 라이트 | 게임 기획 | **Codex** gpt-6.1-sol · medium | 시스템·창발·플레이어 주도성 |

페어 두 사람은 같은 역할 파일(`roles/교육리서치.md` 등)을 쓰고 관점만 다릅니다.
서로의 안을 보지 않고 각자 초안을 쓴 뒤, 상호 비판을 최대 2라운드 하고 결정 요청서를 만듭니다
(`roles/_team-workflow.md` §10).

### 개발 창 — 만드는 쪽 Claude, 검증하는 쪽 Codex

| 이름 | 역할 | 엔진 · 모델 · effort | 핵심 책임 |
|---|---|---|---|
| 네이선 | 아키텍트 | Claude Opus 5.5 · xhigh | ADR, 콘텐츠·학습 데이터 모델, 클라이언트·서버 경계, 구현 가이드 |
| 마크 | 백엔드 개발 | Claude Opus 5.5 · xhigh | 서버·API, 콘텐츠 처리 도구, 학습 이벤트 수집, TDD |
| 이와타 | 클라이언트 개발 | Claude Opus 5.5 · xhigh | 게임·앱 화면, 조작, 오프라인, 크로스플랫폼 배포, TDD |
| 정민 | QA · 리뷰 게이트 | **Codex** gpt-6.1-sol · high | 보안·품질·커버리지, 아동 개인정보·스토어 정책·다크패턴 점검, ADR 반론 |
| 카맥 | 성능 게이트 | **Codex** gpt-6.1-sol · medium | 저사양 기기 기준 프레임·로딩·용량·배터리, ADR 반론 |
| 수진 | 리서처 | Claude Sonnet 5.5 (1M) · medium | 엔진·기술 비교, 경쟁 앱·시장, 플랫폼 정책 사실 확인 |
| 수영 | 디자인 리드 | Claude Opus 5.5 · high | UI/UX, 아트 방향·스타일 가이드, 접근성, 아동 친화 화면 |
| 히사이시 | 음악 감독 · 아트·사운드 에셋 | Claude Sonnet 5.5 (1M) · medium | 테마 선율·음악 큐, 에셋 명세·조달·라이선스. 외부 도구는 매번 최신 조사 후 사용자 결정 |

### 내러티브 게임 팀 (`teams/narrative.conf`, 14명)

영화 같은 시나리오로 플레이어가 주인공이 되고, 엔딩에서 깊은 감동을 주는 게임을 위한 팀입니다.
교육 리서치·콘텐츠 기획 페어 대신 아래 멤버가 기획 창에 들어가고, 개발 창은 학습 게임 팀과 같습니다.

| 이름 | 역할 | 엔진 · 모델 · effort | 핵심 책임 |
|---|---|---|---|
| 우에다 | 디렉터 | Claude Opus 5.5 · high | 톤 바이블·감정 지도·연출 방향·일관성 검수. **작은 창작 판단을 위임받아** 판단·기록 (§13) |
| 닥터 | 시나리오 기획 | Claude Opus 5.5 · high | 인물·감정 중심 — 주인공이 무엇을 원하고 잃는가 |
| 드럭만 | 시나리오 기획 | **Codex** gpt-6.1-sol · medium | 구조·긴장 중심 — 복선 회수, 엔딩까지의 정직한 축적 |

```bash
setup-team narrative -d ~/MyProject/<내러티브 프로젝트 폴더> -c narrative
```

- 디렉터 위임: 대사 문구 다듬기, 장면 안 연출 세부, 음악 큐 위치 등은 우에다가 판단하고
  `docs/direction/delegated-log.md` 에 기록합니다. 줄거리·결말·인물의 운명·분기 구조·톤 바이블은 사용자가 결정합니다.
- 팀 설정의 `@project` 줄이 각 멤버 정체 블록에 표시되어, 공용 역할 파일의 유형별 항목(학습 게임 / 내러티브 게임)을 골라 적용합니다.
- 두 팀을 동시에 띄우면 Codex 계정 한도를 함께 씁니다.

엔진·모델·effort·창 배치는 `teams/edu-game.conf` 에서 바꿉니다. 개편 전 7명 구성은 `teams/backend.conf` 에 있습니다
(`setup-team -c backend`). 역할 파일은 공용이므로 이 구성에서도 제임스는 진행자로 동작합니다.

- 같은 모델끼리 같은 실수를 놓치는 위험을 줄이려고 검증 게이트(정민·카맥)를 다른 모델(Codex)로 둡니다.
- Codex 멤버 5명은 계정 사용 한도를 공유합니다. 기획 페어는 effort medium 으로 시작해
  `team-status --limits` 로 소모를 보고 조정하세요(§0.5.1).
- `claude-fable-5-1` 은 기본 배정하지 않습니다. 필요할 때만 해당 페인에서 `/model fable` 로 전환하세요.
- effort 는 실행 시 전달되며(Claude `--effort`, Codex `model_reasoning_effort`), 페인 안에서 세션 단위 조정도 가능합니다.

실행 시 각 멤버에게 **정체 블록**(이름·엔진·창·페어 상대) + 공통 워크플로 + 역할 파일이 합쳐져 주입됩니다
(`roles/.merged/<세션>/<이름>.md` — 세션별 폴더라 여러 팀을 동시에 띄워도 섞이지 않음).

### 협업 흐름 요약

| 요청 유형 | 흐름 |
|---|---|
| 기획 쟁점 (학습 방식·콘텐츠·게임성) | 제임스 쟁점 정의 → 해당 페어 독립 초안 → 상호 비판(≤2라운드) → 결정 요청서 → **사용자 결정** → 개발 인계(§12) |
| 기술 선택 (엔진·라이브러리) | 수진 조사 → 네이선 ADR 초안 → 정민·카맥 반론 → 제임스 상정 → **사용자 결정** |
| 신규 기능 구현 | 네이선 구현 가이드 → 마크(서버)·이와타(클라이언트) TDD·PR → 정민·카맥(+`interface-change` 시 네이선) 병렬 게이트 → 머지 |
| 버그 | 제임스 → 정민(재현·심각도) → 마크·이와타 수정 → 정민 리뷰 |
| 외부 에셋 도구 | 히사이시 최신 조사(출처·날짜·상업/아동 이용 조건) → 제임스 상정 → **사용자 결정** |
| 릴리스 | 정민·카맥 검증 통과 → 제임스 상정 → **사용자 승인** → `main` 머지 |

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

### 팀 설정 (`teams/*.conf`)

팀 구성은 `teams/` 의 팀 설정 파일이 단일 소스입니다(형식·배정 원칙은 `teams/README.md`). `setup-team.sh` 는 이 파일로 페인 레이아웃·라벨·
모델·effort·역할 주입을 만들고, `team-send` 는 같은 파일로 수신자 이름·별칭을 페인 인덱스로 바꿉니다.

```
# 이름 | 역할파일 | 페인 라벨 | 엔진 | 모델 | effort | 별칭(공백 구분)
제임스 | 제임스       | 제임스 CTO             | claude | claude-opus-5-5 | high  | james cto
정민   | 정민         | 정민 QA·Reviewer       | codex  | gpt-6.1-sol     | xhigh | jungmin qa reviewer
```

- **행 순서 = 멤버 번호.**
- **`@project <설명>` 줄**은 프로젝트 종류입니다. 멤버 정체 블록에 표시됩니다.
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
  `team-send` 는 이를 먼저 읽습니다(없으면 `TEAM_MEMBERS_FILE` → 기본 `teams/idea.conf`).
  그래서 `-c` 로 띄운 세션에서도 `team-send` 가 같은 구성을 씁니다.
- 각 페인에는 멤버 번호 태그 `@member` 가 붙고, `team-send`·`team-status` 는 tmux 인덱스가 아니라 이 태그로
  페인을 찾습니다. 그래서 `~/.tmux.conf` 의 `base-index`·`pane-base-index` 설정과 무관하게 동작합니다.
- 멤버 기동 전에 멤버마다 태그 페인이 하나이고 `@role` 라벨이 일치하는지 검증하고, 불일치 시 세션을 종료합니다.

### Codex 엔진

- 역할 지시는 `-c developer_instructions` 로 주입합니다(공통 워크플로 + 역할 파일, ~45KB). 긴 지시를 페인에
  타이핑하지 않도록 `roles/.merged/<세션>/<이름>.codex.sh` 실행 스크립트를 만들어 호출합니다.
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
2. 해당 팀 설정(`teams/<팀>.conf`)에 한 줄 추가
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
- 프로젝트마다 인원·모델이 다르면 가까운 `teams/*.conf` 를 복사해 수정하고 `setup-team -c <이름>` 으로 띄웁니다. 보통은 아이디어 팀이 팀 구성안을 제안합니다(§14).
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
