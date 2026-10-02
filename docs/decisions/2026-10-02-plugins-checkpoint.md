# ADR: 멤버별 플러그인 부여와 체크포인트 자동 저장 훅

- 상태: **Accepted**
- 일자: 2026-10-02
- 의사결정자: 사용자
- 작성: Claude Code 세션 (사용자와의 대화로 확정한 내용을 기록)

## 1. 맥락

- 역할 파일의 "우선 활용 스킬" 목록(수십 개)은 서드파티 ECC 플러그인 스킬 이름이었고 **하나도 설치되어 있지 않았다.** 공통 워크플로가 가리키던 `~/.claude/rules/ecc/*` 도 없었고, Codex 사용자 스킬 경로를 `~/.codex/skills` 로 잘못 적었다(공식: `~/.agents/skills`).
- 공식 저장소(Claude: `anthropics/claude-plugins-official`, Codex: `openai/plugins` · `openai-curated-remote`)에 역할에 맞는 플러그인이 있었다.
- 컨텍스트 정리 전 체크포인트 저장(§0.5)이 제임스의 수동 지시에만 의존했다.

## 2. 결정

1. 역할 파일의 존재하지 않는 스킬 목록을 지우고 "도구" 절로 바꾼다 — 기준은 정체 블록의 **"부여된 플러그인"**.
2. 권장 플러그인을 설치·연결한다.
   - Claude: `feature-dev`, `code-simplifier`, `security-guidance`, `frontend-design`, `playground`, `playwright`, `context7`
   - Codex: `codex-security`, `game-studio`, `build-web-apps`, `product-design`
3. **멤버별 부여** — 팀 설정 8번째 열 "플러그인".
4. **체크포인트 자동 저장 훅** — `bin/team-checkpoint`.

## 3. 구현과 검증에서 확인한 사실

| 항목 | 확인 내용 | 대응 |
|---|---|---|
| Claude 멤버별 플러그인 | `--plugin-dir` 로 세션 단위 로드 가능. 공식 마켓플레이스 사본에 7개 모두 로컬 폴더로 존재 | 전역 설치 없이 멤버 세션에만 로드 |
| Codex 플러그인 설치 | `codex plugin add <이름>@openai-curated-remote` 로 설치하면 기본 활성 | `~/.codex/config.toml` 에 `enabled = false` 추가 (설정 백업 후) |
| Codex `-c plugins.<id>.enabled` | 키에 따옴표를 쓰면 적용 안 됨. `exec` 에서는 동작하지만 **대화형에서는 원격 설치 플러그인의 enabled 를 따르지 않음** | 부여되지 않은 관리 대상 플러그인의 스킬을 `skills.config` 로 경로 단위 비활성화 → 대화형에서 정확히 부여분만 노출 확인 |
| Codex 공유 서버 | 대화형은 공유 백그라운드 서버에 붙음 | `--no-daemon` 으로 멤버마다 독립 프로세스 |
| `security-guidance` | 첫 실행 때 `~/.claude/security/agent-sdk-venv` 에 전용 venv. README 가 공유 작업 폴더 다중 에이전트 환경에서 턴 종료 리뷰를 끄라고 권장 | 해당 멤버에 `ENABLE_STOP_REVIEW=0` |
| Claude 훅 | `PreCompact` 는 문맥 주입 불가, 정리 후 `SessionStart(source=compact)` 에서 `additionalContext` 가능. `--settings` 로 세션 단위 등록 | 저장은 PreCompact, 복구 지시는 SessionStart |
| Codex 훅 | `PreCompact`·`PostCompact` 는 공통 필드만(문맥 주입 불가 — 반환하면 "invalid hook JSON"). `SessionStart(compact)` 는 **다음 모델 요청 직전**에 실행 | 저장 후 대기 표시, `SessionStart(compact)` + `UserPromptSubmit` 중 먼저 오는 쪽에서 1회 주입 |
| Codex `-c` 훅 신뢰 | 신뢰 저장이 없어 그대로는 실행 안 됨 | `--dangerously-bypass-hook-trust` (그 실행 한정, `~/.codex/hooks.json` 사용자 훅도 함께 실행) |
| 한글 멤버 이름 | `printf %q` 로 감싸면 페인의 zsh 에서 바이트가 깨짐 | 큰따옴표로만 감쌈 |

실측: Claude·Codex 각각 `/compact` 실행 → 자동 체크포인트 저장 → 정리 후 멤버가 파일 조회 없이 체크포인트 경로를 답함. 멤버별 플러그인은 Claude(6개 로드)·Codex(부여 2개만 노출) 모두 확인.

## 4. 결과

- 플러그인은 사용자 전역에서 켜지지 않는다 — 사용자 개인 Claude Code·Codex 세션에는 나타나지 않는다.
- 공통 워크플로 "실행 전 체크"를 정체 블록 기준으로 바꾸고, §0.5 에 자동 체크포인트(안전망)를 추가했다.
- 추가 후보(결정 시점에 다시 판단): `unity`, `typescript-lsp`, `sentry`, `posthog`, `consensus`, `figma`.

## 5. 재평가

- Codex 가 대화형에서 원격 플러그인 enabled 설정을 따르게 되면 `skills.config` 우회를 제거한다.
- 자동 체크포인트가 실제 auto-compact 에서 쓸모 있었는지 첫 장기 작업 후 점검한다.
