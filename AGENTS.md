# Repository instructions

Read `CLAUDE.md` for the repository's contribution, testing, and release instructions.

## 작업환경 및 개발 규칙

### Chrome 접근 권한

- 이 프로젝트에서 접근할 수 있는 Chrome 화면은 `yongyong92.05@gmail.com` 계정으로 로그인한 화면으로 한정한다.
- 브라우저 작업을 시작하기 전에 Chrome 프로필과 실제 로그인 계정을 확인한다. 프로필 이름만으로 계정을 추정하지 않는다.
- 다른 계정으로 로그인한 화면이나 프로필에는 접근하거나 작업하지 않는다. 지정된 계정을 확인할 수 없으면 브라우저 작업을 중단하고 사용자에게 알린다.

### 디렉토리 및 코드 명명

- 디렉토리 이름과 코드 식별자에 `codex` 등 AI 제품·도구·모델을 직접 드러내는 명칭을 사용하지 않는다.
- 파일명, 모듈명, 타입명, 메서드명, 변수명은 제품의 도메인과 실제 책임을 설명하는 중립적인 이름으로 정한다.

### 파일 단위 모듈화 및 클린 코드

- 메서드는 기능과 책임에 따라 파일 단위 모듈로 분리한다. 서로 관련된 메서드는 같은 모듈에 모으고, 다른 책임은 별도 파일로 분리한다.
- UI 표현, 도메인 로직, 상태 관리, 영속성 및 외부 연동의 책임을 분리하고 명시적인 인터페이스로 연결한다.
- 거대한 파일과 메서드, 중복 구현, 숨은 의존성을 피하고 단일 책임과 테스트 가능한 구조를 유지한다.
- 상태와 데이터는 일관되게 정규화하고, 동시성 안전성과 실시간 반영을 우선한다. 변경한 동작은 실제 테스트로 검증한다.

## Pull requests

When creating, preparing, or updating a PR, use `.agents/skills/prepare-pr/SKILL.md`. This repository's rules take precedence over a personal PR skill's default title or body format.

Use an English Conventional Commits title and fill out `.github/PULL_REQUEST_TEMPLATE.md` with the actual changes and validation results. Mark checklist items complete only when supported by the work performed.

Every PR with a visible UI change must embed images in `UI changes`: actual screenshots, local renders of the production UI, or clearly labeled illustrations of the changed UI are accepted. Include before/after images for an existing screen; for a new screen, explain that no previous screen exists and include its image. Text alone does not satisfy this requirement. If images are missing, the agent must produce and attach them as part of the authorized PR work without asking the user to supply them. Try suitable generation and attachment alternatives before declaring a blocker. Keep publication pending only when a concrete failure still prevents completion, and report the attempted methods and required user action. Remove `UI changes` only when there is no visible UI change.
