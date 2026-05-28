# claude-ecg-team

tmux + Claude Code 로 다중 페르소나(역할별 페인)를 자동 구성하는 팀 셋업 도구입니다.
한 터미널에 7개 역할의 Claude 인스턴스를 동시에 띄우고, 페인 간에 메시지를 주고받으며
실제 팀처럼 협업할 수 있습니다.

## 의존성

- `tmux`
- `claude` CLI (`@anthropic-ai/claude-code`)

## 사용법

```bash
bash setup-team.sh [세션이름] [-d <작업디렉터리>]
```

- `세션이름` 기본값은 `team`
- `-d` 미지정 시 현재 디렉터리를 작업 디렉터리로 사용

세션 진입은 `tmux attach -t <세션이름>` 입니다.

## 디렉터리 구조

```
.
├── setup-team.sh           # tmux 멀티페인 자동 셋업 (메인)
├── ex-setup.sh             # 이전 버전 셋업 (참고용)
├── bin/
│   ├── team-send           # 페인 간 메시지 전송 헬퍼
│   └── team-status         # 페인 상태 확인 헬퍼
└── roles/
    ├── _team-workflow.md   # 모든 페르소나 공통 워크플로
    ├── 제임스.md            # 페르소나별 역할 정의
    ├── 수진.md
    ├── 정민.md
    ├── 카맥.md
    ├── 네이선.md
    ├── 수영.md
    └── 마크저커버그.md
```

## 페르소나

| 이름 | 역할 |
|---|---|
| 제임스 | 팀 오케스트레이터 / 의사결정 허브 |
| 수진 | 시스템 / 인프라 |
| 정민 | 백엔드 / 데이터 |
| 카맥 | 성능 / 저수준 시스템 |
| 네이선 | 아키텍처 / ADR |
| 수영 | QA / 검증 |
| 마크저커버그 | 프로덕트 / 실행 |

세부 역할 정의는 `roles/<이름>.md` 와 공통 워크플로 `roles/_team-workflow.md` 를
참조하세요.

## 페인 간 통신

```bash
# 다른 페인에게 메시지 보내기
bin/team-send <대상페르소나> "<메시지>"

# 모든 페인의 마지막 출력 확인
bin/team-status --tail 2
```

`setup-team.sh` 가 `bin/` 을 PATH 에 자동 추가하므로 페인 내부에서는 `team-send`,
`team-status` 를 그대로 호출할 수 있습니다.

## 빌드 산출물

`roles/.merged/` 는 `setup-team.sh` 가 공통 워크플로와 역할 파일을 합쳐서 만드는
런타임 합성 결과물입니다. 매 실행마다 새로 생성되므로 절대 커밋하지 않습니다
(`.gitignore` 처리됨).
