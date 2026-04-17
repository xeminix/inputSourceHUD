# Claude Code 개발 가이드

> 공통 규칙(Agent Delegation, 커밋 정책, Context DB 등)은 글로벌 설정(`~/.claude/CLAUDE.md`)을 따릅니다.
> 글로벌 미설치 시: `curl -fsSL https://raw.githubusercontent.com/leonardo204/dotclaude/main/install.sh | bash`

---

## Slim 정책

이 파일은 **100줄 이하**를 유지한다. 새 지침 추가 시:
1. 매 턴 참조 필요 → 이 파일에 1줄 추가
2. 상세/예시/테이블 → ref-docs/*.md에 작성 후 여기서 참조
3. ref-docs 헤더: `# 제목 — 한 줄 설명` (모델이 첫 줄만 보고 필요 여부 판단)

---

## PROJECT

### 개요

**InputSourceHUD** — macOS 앱별 입력 소스 자동 전환 + 커스터마이징 HUD 메뉴바 유틸리티

| 항목 | 값 |
|------|-----|
| 기술 스택 | macOS 15+, Swift 5.9+, SwiftUI + AppKit(NSPanel), UserDefaults, Sparkle 2.x, KeyboardShortcuts |
| 빌드 방법 | Xcode 프로젝트 (.xcodeproj), Universal Binary (arm64 + x86_64) |
| Bundle ID | com.codequa.inputSourceHUD |
| 상태 | 개발 전 (기획 완료) |

### 상세 문서

- [Context DB](Ref-docs/claude/context-db.md) — SQLite 기반 세션/태스크/결정 저장소
- [Context Monitor](Ref-docs/claude/context-monitor.md) — HUD + compaction 감지/복구
- [컨벤션](Ref-docs/claude/conventions.md) — 커밋, 주석, 로깅 규칙
- [셋업](Ref-docs/claude/setup.md) — 새 환경 초기 설정
- [기획 및 개발 계획](Ref-docs/InputSourceHUD-Plan.md) — PRD + 아키텍처 + 개발 로드맵

### 핵심 규칙

- TIS API (Carbon) 사용 — InputSource 조회/변경 유일 수단
- HUD는 NSPanel + nonactivatingPanel — 포커스 훔치지 않음
- 샌드박스 OFF (Hardened Runtime ON)
- LSUIElement = YES (Dock 미표시, 메뉴바 앱)

---

*최종 업데이트: 2026-04-16*
