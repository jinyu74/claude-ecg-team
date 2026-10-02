# 팀 설정 (`teams/*.conf`)

팀 구성의 단일 소스입니다. `setup-team.sh` 는 이 파일로 tmux 창·페인 배치, 라벨, 엔진·모델·effort, 역할 주입을 만들고,
`team-send` 는 같은 파일로 수신자 이름·별칭을 찾습니다.

| 파일 | 팀 | 인원 (Claude : Codex) | 용도 |
|---|---|---|---|
| `idea.conf` | 아이디어 팀 (**기본값**) | 10 (5 : 5) | 초기 리서치·컨셉 발산·수렴 → 컨셉·프로젝트 유형·프로젝트 팀 구성 결정 (공통 워크플로 §14) |
| `edu-game.conf` | 학습 게임 팀 | 15 (10 : 5) | 재미있고 교육적인 게임 |
| `narrative.conf` | 내러티브 게임 팀 | 14 (10 : 4) | 영화 같은 시나리오·엔딩의 감동 |
| `backend.conf` | 백엔드 팀 (개편 전) | 7 (5 : 2) | 백엔드 서비스 |

```bash
setup-team ideas -d ~/MyProject/ideas              # -c 생략 → teams/idea.conf
setup-team edu   -d ~/MyProject/edu-game -c edu-game   # 이름만 쓰면 teams/<이름>.conf
setup-team story -d ~/MyProject/<폴더>  -c ./my-team.conf # 경로도 가능
```

## 형식

```
@project <설명>                                    # 프로젝트 종류 — 멤버 정체 블록에 표시
[창이름]                                           # 이후 멤버를 이 tmux 창에 배치
이름 | 역할파일 | 페인 라벨 | 엔진 | 모델 | effort | 별칭(공백 구분) | 플러그인(공백 구분, 선택)
```

| 열 | 내용 |
|---|---|
| 이름 | `team-send` 수신자·메시지 헤더에 쓰는 대표 이름 |
| 역할파일 | `roles/<역할파일>.md` (확장자 제외). 없으면 경고 후 역할 없이 기동. 페어는 같은 역할 파일을 쓴다 |
| 페인 라벨 | tmux 페인 보더와 `team-status` 역할 칸 |
| 엔진 | `claude` \| `codex` |
| 모델 | claude: `claude-opus-5-5` · `claude-sonnet-5-5[1m]` … / codex: `gpt-6.1-sol` … |
| effort | `low` · `medium` · `high` · `xhigh` · `max` (claude `--effort`, codex `model_reasoning_effort`) |
| 별칭 | `team-send` 수신자로 쓸 수 있는 추가 이름 |
| 플러그인 | 이 멤버에게만 부여할 플러그인 (선택). 엔진에 맞는 이름을 쓴다 — 아래 "플러그인" |

- **행 순서 = 멤버 번호** (0부터, 페인 태그 `@member`). 같은 창의 멤버는 연속으로 적는다(같은 창 이름 중복 불가).
- 구획이 없으면 창 `team` 하나. 창마다 첫 멤버는 좌측 메인 페인, 나머지는 우측 2열 그리드에 행 우선 배치.
- 형식 오류·중복 이름/라벨·잘못된 엔진·effort·알 수 없는 `@` 지시어는 tmux 세션을 만들기 전에 중단된다.

## 플러그인 (2026-10-02)

멤버별로 부여한다. 사용자 전역 설정에는 켜지 않으므로 사용자의 개인 Claude Code·Codex 세션에는 나타나지 않는다.

| 엔진 | 출처 | 부여 방식 |
|---|---|---|
| Claude | 공식 마켓플레이스 사본 `~/.claude/plugins/marketplaces/claude-plugins-official` (Claude Code 가 자동 갱신) | 그 멤버 세션에만 `--plugin-dir` 로 로드 |
| Codex | 공식 `openai-curated-remote` 마켓플레이스에서 설치 (`codex plugin add <이름>@openai-curated-remote`) | 전역은 `~/.codex/config.toml` 에서 끄고, 멤버에게 부여되지 않은 관리 대상 플러그인의 스킬을 `skills.config` 로 경로 단위 비활성화 |

| 플러그인 | 엔진 | 용도 | 부여 (edu-game 기준) |
|---|---|---|---|
| `feature-dev` | Claude | 코드베이스 탐색·아키텍처 설계·구현 흐름 | 네이선·마크·이와타 |
| `code-simplifier` | Claude | 코드 간결화 (품질 원칙 3) | 마크·이와타 |
| `security-guidance` | Claude | 편집 시 보안 패턴 경고·커밋 리뷰 (턴 종료 리뷰는 공유 작업 폴더라 끔: `ENABLE_STOP_REVIEW=0`) | 마크·이와타 |
| `frontend-design` | Claude | 완성도 높은 UI 구현 | 이와타·수영 |
| `playground` | Claude | 인터랙티브 HTML 프로토타입 | 수영·미야모토 (+우에다, 아이디어 팀) |
| `playwright` | Claude | 브라우저 자동화·E2E (MCP, `npx`) | 이와타 |
| `context7` | Claude | 최신 라이브러리 문서 조회 (원격 MCP) | 마크·이와타·수진 |
| `codex-security` | Codex | 보안 스캔·위협 모델·변경분 보안 검사 | 정민 |
| `build-web-apps` | Codex | 프런트엔드 테스트·디버깅 | 정민·카맥 |
| `game-studio` | Codex | 브라우저 게임 설계·플레이테스트·Phaser 2D | 라이트·카맥 |
| `product-design` | Codex | 아이디어 발산·리서치·디자인 점검 | 아이디어 팀 Codex 멤버 |

- 새 Codex 플러그인을 쓰려면 먼저 설치하고, `~/.codex/config.toml` 에 `[plugins."<이름>@openai-curated-remote"] enabled = false` 를 추가해 전역에서 끈다.
- 없는 플러그인 이름은 `setup-team` 이 기동 전에 경고하고 건너뛴다.
- 엔진·엔진 결정에 따라 추가 후보: `unity`(Unity 채택 시), `typescript-lsp`(TypeScript 채택 시), 출시 후 `sentry`·`posthog`.

## 배정 원칙 (2026-10-02)

- **Claude Opus 5.5** — 진행·기획 판단·설계·구현·디자인 리드
- **Claude Sonnet 5.5 (1M)** — 조사·에셋처럼 반복 많고 컨텍스트 큰 작업
- **Codex gpt-6.1-sol** — 결정 페어의 다른 관점, 개발 검증 게이트. 웹 검색(`--search`) 켜짐, 기동 시 업데이트 확인 꺼짐
- **Fable 5.1** — 기본 배정 안 함 (필요 시 페인에서 `/model fable`)
- effort: 구현·설계 `xhigh`, 기획 판단·진행·디자인 `high`, 조사·에셋·Codex 기획 페어 `medium`
- Codex 멤버는 계정 사용 한도를 공유한다. 여러 팀을 동시에 띄우면 함께 쓴다 — `team-status --limits` (공통 §0.5.1)

## 새 팀 만들기

아이디어 팀에서 컨셉이 결정되면 제임스가 가장 가까운 팀 설정을 출발점으로 `teams/<프로젝트>.conf` 초안을 제안하고,
사용자가 구성을 결정한다(공통 §14). 직접 만들 때는 기존 파일을 복사해 수정한다.
