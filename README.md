# claude-ecg-team

tmux + Claude Code 로 다중 페르소나(역할별 페인)를 자동 구성하는 팀 셋업 도구입니다.
한 터미널에 7개 역할의 Claude 인스턴스를 동시에 띄우고, 페인 간에 메시지를 주고받으며
실제 팀처럼 협업할 수 있습니다.

## 의존성

- `tmux`
- `claude` CLI (`@anthropic-ai/claude-code`)
- `jq` (선택 — team-send-verify Hook 동작에 필요. 미설치 시 Hook 만 graceful skip)

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
