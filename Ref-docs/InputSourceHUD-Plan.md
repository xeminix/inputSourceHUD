# InputSourceHUD — 기획 및 개발 계획

> macOS 앱별 입력 소스 자동 전환 + 커스터마이징 가능한 HUD

**작성일**: 2026-04-16
**문서 버전**: 0.1 (초안)
**리포지토리**: https://github.com/xeminix/inputSourceHUD
**Bundle ID**: `com.codequa.inputSourceHUD`

---

## 1. 제품 개요

### 1.1 한 줄 설명
macOS에서 앱을 전환할 때마다 원하는 입력 소스(언어)로 자동 변경해주고, 변경 사실을 아름다운 HUD로 알려주는 메뉴바 유틸리티.

### 1.2 해결하는 문제
- macOS는 앱별로 "마지막 사용한 입력 소스"를 기억하는데, 이 동작이 일관되지 않아 혼란을 준다.
- 특정 앱(예: Xcode, Terminal)은 항상 영어를, 다른 앱(예: Slack, 메신저)은 한글을 쓰고 싶은 니즈를 표준 macOS가 충족시키지 못한다.

### 1.3 차별화 포인트
| 항목 | 설명 |
|---|---|
| 커스터마이징 가능한 HUD | 스타일/위치/지속시간/표시내용을 사용자가 선택 |
| 멀티 모니터 지원 | 마우스 커서가 있는 모니터에 HUD 표시 |
| Sparkle 기반 지속 업데이트 | 1회 구매 후 지속적인 기능 개선 |
| 한국어 UX 최적화 | 한/영 전환 시나리오에 특화된 기본값 |

### 1.4 비즈니스 모델
- **1회 유료 구매** (라이선스 방식은 v1 이후 결정)
- 지속적인 기능 업데이트 제공
- 현재는 **내부 사용 목적**으로 개발 (public 배포는 추후 결정)

---

## 2. 타겟 사용자 / 시나리오

### 2.1 타겟 사용자
- 다국어(한/영 등) 입력을 자주 전환하는 macOS 사용자
- 개발자, 번역가, 이중 언어 사용 직장인

### 2.2 대표 시나리오
- **Xcode/Terminal 전환 시 영어 고정**: 코드 작성 중 한영 전환 깜빡임 제거
- **Slack/카카오톡 전환 시 한글 고정**: 메시지 타이핑 즉시 시작
- **특정 앱에서는 macOS 기본 동작 유지**: 강제 변경 제외 가능

---

## 3. 기능 사양 (MVP)

### 3.1 기능 목록

#### MVP 핵심 (v0.1)

##### F1. 앱별 입력 소스 강제
- 포그라운드 앱이 변경되면 해당 앱에 지정된 입력 소스로 자동 전환
- 앱마다 3가지 정책 중 하나 선택:
  - (a) 특정 입력 소스로 강제
  - (b) 전역 디폴트 사용
  - (c) macOS 기본 동작 유지 (건드리지 않음)
- 선택 가능한 입력 소스는 사용자가 시스템 설정에 추가해둔 것만 노출

##### F2. 전역 디폴트 입력 소스
- 앱별 설정이 없는 경우 자동 적용될 기본 입력 소스
- 설정이 없는 앱 → 디폴트로 변경

##### F4. HUD 오버레이
- 입력 소스 변경 시 시각적 피드백
- **기본 스타일**: macOS 볼륨 HUD 스타일 (반투명 블러 + 큰 아이콘)
- **표시 내용**: 앱 아이콘/이름 + 언어 이름 (예: `Safari → English`)
- **표시 위치**: 마우스 커서가 있는 모니터의 중앙
- **기본 표시 시간**: 1초 (0.3s ~ 3s 커스터마이즈)
- **포커스 훔치지 않음**: `NSPanel` + `nonactivatingPanel`
- **Secure Input 상태**: HUD로만 알림, 실제 변경은 skip

##### F6. 메뉴바 아이콘
- Dock/App Switcher에는 표시 안 함 (`LSUIElement = YES`)
- 현재 활성 입력 소스를 아이콘에 표시 (예: `ABC` / `한`)
- 메뉴에서 전역 ON/OFF, 설정 열기, 현재 앱 설정 바로가기, 종료

##### F7. 런치앳로그인
- macOS 13+ `SMAppService.mainApp` 사용
- 설정 화면에서 ON/OFF

##### F11. 로컬라이제이션
- 한국어 / 영어 (최소 2개 언어)

#### MVP 축소 포함 (v0.1)

##### F3. 블랙리스트(예외 앱) 모드
- **블랙리스트**: 등록된 앱 제외 전부 디폴트로 변경
- 화이트리스트 모드 및 모드 전환은 v1.1에서 추가

##### F5. HUD 커스터마이징 (축소)
- 볼륨 HUD 스타일 1종
- 지속 시간 슬라이더
- HUD 전체 ON/OFF
- 3종 스타일(볼륨/토스트/미니), 앱별 HUD 표시 여부는 v1.1에서 추가

#### v1.1 이후

##### F8. Sparkle OTA 업데이트
- Sparkle 2.x + EdDSA 서명
- GitHub Pages에 `appcast.xml` 호스팅
- 설정 화면에 "Check for Updates" 버튼
- 내부용이면 수동 빌드로 시작, v1.1에서 Sparkle 통합

##### F9. 설정 Export / Import
- JSON 파일로 전체 설정 내보내기 / 가져오기
- 다른 Mac 이관용

##### F10. 글로벌 단축키
- 기능 전체 ON/OFF 토글 단축키
- `MASShortcut` 또는 `KeyboardShortcuts` (Sindre Sorhus) 라이브러리 사용
- MVP에서는 메뉴바 토글로 대체

### 3.2 제외 사항 (v2 이후 고려)
- 브라우저 URL별 입력 소스
- Shortcuts.app 통합
- iCloud 동기화
- 창/문서 단위의 세밀한 제어
- Mac App Store 배포
- ~~F8 Sparkle OTA~~ → v1.1
- ~~F9 Export/Import~~ → v1.1
- ~~F10 글로벌 단축키~~ → v1.1 (MVP는 메뉴바 토글로 대체)
- F3 화이트리스트 모드 전환 → v1.1
- F5 3종 스타일, 앱별 HUD 표시 여부 → v1.1

---

## 4. 기술 아키텍처

### 4.1 스택
| 항목 | 선택 |
|---|---|
| 최소 OS | macOS 15.0 (Sequoia) 이상 |
| 아키텍처 | Universal Binary (arm64 + x86_64) |
| UI | SwiftUI (HUD는 NSPanel + AppKit 혼용) |
| 언어 | Swift 5.9+ |
| 프로젝트 | Xcode `.xcodeproj` |
| 저장소 | UserDefaults (+ JSON Export/Import) |
| 업데이트 | Sparkle 2.x *(v1.1)* |
| 단축키 | KeyboardShortcuts (Sindre Sorhus) *(v1.1)* |
| 로그 | OSLog (`os.Logger`) |
| 서명 | Developer ID + Notarization |

### 4.2 모듈 구조

```
InputSourceHUD/
├── App/
│   ├── InputSourceHUDApp.swift          # @main, AppDelegate, SMAppService
│   └── AppEnvironment.swift              # DI 컨테이너
│
├── Core/                                 # 도메인 로직 (UI 독립)
│   ├── InputSource/
│   │   ├── InputSource.swift             # 값 타입 (id, name, icon)
│   │   ├── InputSourceManager.swift      # TIS API 래퍼
│   │   └── InputSourceChangeObserver.swift  # 전역 입력 소스 변경 감지
│   ├── AppSwitching/
│   │   ├── AppSwitchObserver.swift       # NSWorkspace 알림 + debounce
│   │   └── AppSwitchCoordinator.swift    # 감지 → 정책 → 전환 오케스트레이션
│   ├── Policy/
│   │   ├── AppPolicy.swift               # 앱별 규칙 (enum: forced/default/ignore)
│   │   ├── PolicyStore.swift             # 규칙 저장/조회
│   │   └── ListMode.swift                # whitelist/blacklist
│   └── SecureInput/
│       └── SecureInputDetector.swift     # IsSecureEventInputEnabled()
│
├── Features/
│   ├── HUD/
│   │   ├── HUDWindowController.swift     # NSPanel 관리
│   │   ├── HUDWindow.swift               # NSPanel 서브클래스
│   │   ├── HUDStyle.swift                # 볼륨/토스트/미니 enum
│   │   ├── HUDContentView.swift          # SwiftUI 렌더링
│   │   └── ScreenLocator.swift           # 마우스 기반 모니터 찾기
│   ├── MenuBar/
│   │   ├── MenuBarController.swift       # NSStatusItem
│   │   └── MenuBarIconRenderer.swift     # 현재 소스 텍스트 렌더
│   ├── Settings/
│   │   ├── SettingsWindow.swift          # SwiftUI Window
│   │   ├── GeneralTab.swift
│   │   ├── AppsTab.swift                 # 앱 목록 + 규칙 편집
│   │   ├── HUDTab.swift                  # HUD 커스터마이징
│   │   ├── ShortcutsTab.swift
│   │   └── AdvancedTab.swift             # Export/Import, 로그
│   └── LaunchAtLogin/
│       └── LaunchAtLoginManager.swift    # SMAppService 래퍼
│
├── Infrastructure/
│   ├── Storage/
│   │   ├── SettingsStore.swift           # UserDefaults 래퍼 (@AppStorage 대체)
│   │   └── SettingsCodec.swift           # JSON Export/Import
│   ├── Logging/
│   │   └── Log.swift                     # OSLog subsystem 정의
│   └── Updater/
│       └── UpdaterController.swift       # Sparkle 래퍼
│
├── Resources/
│   ├── Assets.xcassets                   # 앱 아이콘, 메뉴바 아이콘
│   ├── Localizable.xcstrings             # 한/영
│   └── Info.plist
│
└── Supporting/
    ├── PrivacyInfo.xcprivacy
    └── InputSourceHUD.entitlements       # 서명용 (샌드박스 없음)
```

### 4.3 핵심 데이터 흐름

```
[사용자가 앱 전환]
       │
       ▼
NSWorkspace.didActivateApplicationNotification
       │
       ▼
AppSwitchObserver ── debounce(100ms) ──►
       │
       ▼
AppSwitchCoordinator
  1. bundleId 추출
  2. PolicyStore에서 규칙 조회
  3. ListMode (whitelist/blacklist) 적용
  4. 대상 InputSource 결정
       │
       ▼
SecureInputDetector 체크 (앱 전환 이벤트 시점에 1회 체크, 주기적 폴링 불필요)
       │
       ├─ Secure Input ON  ─► HUD만 표시, 전환 skip
       │
       ▼
InputSourceManager.switch(to:)  (TIS API)
       │
       ▼
HUDWindowController.show(icon, app, language, on: screen)
       │
       ▼
ScreenLocator.currentMouseScreen() → NSPanel 표시 → fade out
```

### 4.4 주요 API
- `TISCopyCurrentKeyboardInputSource()`, `TISSelectInputSource()`, `TISCopyInputSourceList()`
- `NSWorkspace.shared.notificationCenter.addObserver(forName: .didActivateApplicationNotification)`
- `IsSecureEventInputEnabled()`
- `SMAppService.mainApp.register()`
- `NSEvent.mouseLocation` + `NSScreen.screens` (모니터 탐색)

### 4.5 설정 스키마 (JSON 예시)

```json
{
  "schemaVersion": 1,
  "global": {
    "enabled": true,
    "defaultInputSourceId": "com.apple.keylayout.ABC",
    "listMode": "whitelist",
    "debounceMillis": 100
  },
  "hud": {
    "enabled": true,
    "style": "volume",
    "durationSeconds": 1.0,
    "showAppName": true,
    "showLanguageName": true
  },
  "shortcuts": {
    "toggleEnabled": "⌃⌥⌘I"
  },
  "apps": [
    {
      "bundleId": "com.apple.dt.Xcode",
      "policy": "forced",
      "inputSourceId": "com.apple.keylayout.ABC",
      "showHUD": true
    },
    {
      "bundleId": "com.tinyspeck.slackmacgap",
      "policy": "forced",
      "inputSourceId": "com.apple.inputmethod.Korean.2SetKorean",
      "showHUD": true
    }
  ]
}
```

### 4.6 스키마 마이그레이션
- schemaVersion 누락 또는 현재보다 낮으면 기본값으로 초기화 + 기존 파일 백업
- 마이그레이션 코드는 `SettingsCodec`에 집중

---

## 5. UI/UX 설계 가이드

### 5.1 메뉴바
- 아이콘: monochrome template image + 현재 입력 소스 약어 오버레이
- 좌클릭: 드롭다운 메뉴 (토글, 설정, 현재 앱 빠른 규칙 추가)
- 우클릭: 동일 메뉴 (기본 macOS 패턴 준수)

### 5.2 설정 창 (SwiftUI)
탭 구성:
- **General**: 전역 enable, 디폴트 소스, 블랙리스트(예외 앱) 설정, 런치앳로그인
- **Apps**: 앱 목록 (드래그앤드롭 / 피커 / 현재 실행 중인 앱에서 추가), 앱별 규칙
- **HUD**: 스타일(v0.1은 볼륨 HUD 1종), 시간, 위치(중앙 고정), 표시 항목 토글, 실시간 미리보기
- **Shortcuts**: 글로벌 단축키 지정 *(v1.1)*
- **Advanced**: Export/Import *(v1.1)*, 로그 내보내기, 업데이트 설정 *(v1.1)*, 리셋

### 5.3 HUD 디자인 원칙
- 빠르고 방해되지 않음 (기본 1초)
- 포커스 훔치지 않음
- 화면 공유 감지 옵션 (발표 중 억제)
- 다크/라이트 모드 자동 대응

---

## 6. 개발 계획 (Phased)

### Phase 0 — 프로젝트 셋업 (0.5일)
- [ ] GitHub 레포 초기화 (`xeminix/inputSourceHUD`, public)
- [ ] Xcode 프로젝트 생성 (`com.codequa.inputSourceHUD`)
- [ ] `.gitignore`, `README.md`, `LICENSE` 추가
- [ ] Universal Binary 설정, `LSUIElement = YES`
- [ ] 폴더 구조 스캐폴딩
- [ ] SwiftLint / swift-format 설정 (선택)

### Phase 1 — Core 프로토타입 (2~3일)
**목표: 앱 전환 시 입력 소스가 바뀌는 것을 확인**
- [ ] **TIS API 권한 검증 PoC** — 샌드박스 OFF 환경에서 TISSelectInputSource() 호출 성공 확인, Accessibility 권한 필요 여부 검증
- [ ] `InputSource` 모델 + `InputSourceManager` (TIS 래퍼)
- [ ] 사용 가능한 입력 소스 목록 조회
- [ ] `AppSwitchObserver` + debounce
- [ ] `AppPolicy` + 인메모리 `PolicyStore`
- [ ] `AppSwitchCoordinator` 최소 구현
- [ ] 커맨드라인 로그로 동작 확인
- [ ] **테스트**: `PolicyStore` 규칙 조회 유닛 테스트
- [ ] **테스트**: `AppSwitchCoordinator` 정책 결정 로직 테스트

### Phase 2 — HUD (2~3일)
- [ ] `HUDWindow` (`NSPanel`, nonactivating, floating level)
- [ ] `HUDContentView` (볼륨 HUD 스타일 SwiftUI)
- [ ] `ScreenLocator` — 마우스 커서 모니터 감지
- [ ] `HUDWindowController` — 표시/페이드/타이머
- [ ] 앱 전환 이벤트와 연결
- [ ] **테스트**: `ScreenLocator` 테스트

### Phase 3 — 메뉴바 + 기본 설정 저장 (1~2일)
- [ ] `MenuBarController` (`NSStatusItem`)
- [ ] 현재 입력 소스 아이콘 렌더링 (`MenuBarIconRenderer`)
- [ ] `SettingsStore` — UserDefaults 영속화
- [ ] 메뉴에서 ON/OFF 토글
- [ ] **테스트**: `SettingsStore` 직렬화/역직렬화 테스트

### Phase 4 — Settings UI (5~7일)
- [ ] Settings Window (SwiftUI `Settings` scene)
- [ ] General / Apps / HUD / Advanced 탭
- [ ] 앱 추가 UX (Applications 피커, 드래그앤드롭)
- [ ] HUD 실시간 미리보기
- [ ] 입력 소스 선택 드롭다운 (현재 활성화된 소스만)

### Phase 5 — 부가 기능 (2~3일)
- [ ] `SecureInputDetector`
- [ ] 런치앳로그인 (`SMAppService`)

### Phase 6 — 로컬라이제이션 + 로깅 (1일)
- [ ] `Localizable.xcstrings` 한/영
- [ ] OSLog subsystem 정리
- [ ] 로그 내보내기 기능

### Phase 7 — 배포 준비 (2일)
- [ ] DMG 패키징
- [ ] Developer ID 서명 + 공증 (Fastlane 자동화) — Paster 경험 재활용
- [ ] `PrivacyInfo.xcprivacy` 작성
- [ ] 첫 내부 릴리즈 (v0.1)

### Phase 8 — QA / 버그픽스 (2~3일)
- [ ] 전체화면 앱 테스트
- [ ] Spotlight/Raycast와의 상호작용
- [ ] 멀티 모니터 시나리오
- [ ] Secure Input 경로
- [ ] 외부 키보드 연결/해제
- [ ] Apple Silicon + Intel 양쪽에서 테스트

**총 예상 공수: 약 3~4주 (파트타임 기준 더 길어질 수 있음)**

---

## 7. 빌드 / 배포 전략

### 7.1 서명 / 공증
- Apple Developer ID Application 인증서 사용
- `codesign` → `notarytool submit` → `stapler staple` (Fastlane 자동화)
- Hardened Runtime ON, 샌드박스 OFF

### 7.2 Entitlements
```
com.apple.security.automation.apple-events : (필요 시만)
com.apple.security.cs.allow-jit : NO
com.apple.security.cs.disable-library-validation : NO
```
- 현재 기능 범위로는 특별한 entitlement 필요 없음 (확실하지 않음 — 프로토타입에서 재검증)

### 7.3 Sparkle 배포 플로우
1. 버전 태그 푸시 (`v0.1.0`)
2. Fastlane: build → sign → notarize → staple → DMG 생성
3. Sparkle EdDSA로 DMG 서명
4. `appcast.xml` 업데이트 (GitHub Pages)
5. 앱이 자동으로 업데이트 탐지

### 7.4 버전 관리
- SemVer (`MAJOR.MINOR.PATCH`)
- `CFBundleShortVersionString` + `CFBundleVersion` (빌드 번호는 CI/CD에서 auto-increment)

---

## 8. 리스크 / 불확실성

| 항목 | 리스크 | 완화책 | 상태 |
|---|---|---|---|
| Accessibility 권한 필요성 | `NSWorkspace` 알림만으로 충분한지 불확실 | Phase 1에서 실제 테스트, 필요시 권한 요청 플로우 추가 | **확실하지 않음** |
| 전체화면 앱 포커스 감지 | Space 전환과 섞이면 예측 불가 | Phase 8 QA에서 시나리오별 검증 | **확실하지 않음** |
| Secure Input 이벤트 감지 타이밍 | `IsSecureEventInputEnabled()` 호출 시점 | 앱 전환 이벤트 시점에 1회 체크 (폴링 불필요) | 결정됨 |
| TIS API의 `TISSelectInputSource` 실패 | 특정 소스로 전환 실패 케이스 | OSLog로 에러 기록, HUD에 실패 표시(옵션) | 알려진 이슈 |
| Sparkle + Notarization | 공증 실패 시 업데이트 전파 불가 | Fastlane 자동화 + 실패 시 Slack 알림 | 관리 가능 |
| 멀티 모니터 DPI 혼합 | HUD 크기 깨짐 | `backingScaleFactor` 반영, 다양한 해상도 테스트 | 관리 가능 |

---

## 9. 성공 기준 (DoD for v0.1)

- [ ] 5개 이상의 주요 앱에서 앱별 입력 소스 강제가 안정적으로 동작
- [ ] HUD가 마우스 커서 모니터에 1초 이내 표시되고 포커스를 훔치지 않음
- [ ] 메뉴바 아이콘에 현재 입력 소스가 실시간 반영
- [ ] 재부팅 후 설정이 보존되고 자동 실행됨
- [ ] DMG 빌드 + 서명 + 공증이 성공하고, 수동 설치로 동작 확인
- [ ] 크래시 없이 30분 이상 사용 가능 (Console.app `.crash` 없음)

---

## 10. 향후 로드맵 (v1 이후)

- **v1.1**: Sparkle OTA 업데이트(F8), Export/Import(F9), 글로벌 단축키(F10), 화이트리스트 모드 전환(F3), HUD 3종 스타일 + 앱별 HUD 표시 여부(F5), Shortcuts.app 액션, 앱별 HUD 스타일 오버라이드
- **v1.2**: 라이선스 키 시스템, 트라이얼 모드, 공개 배포 준비
- **v1.3**: iCloud 동기화 (선택적)
- **v2.0**: 브라우저 URL별 규칙 (Safari Extension), Mac App Store 버전

---

## 11. 참고 / 결정 기록

| 번호 | 결정 | 근거 |
|---|---|---|
| D-001 | macOS 15.0+ | 최신 API 활용, 사용자층 제한 수용 |
| D-002 | SwiftUI 메인, AppKit 혼용 | HUD는 NSPanel 필수, 설정은 SwiftUI 생산성 |
| D-003 | UserDefaults + JSON Export | 단순성 + 이관 편의성 양립 |
| D-004 | GitHub Pages + Sparkle | 무료, 관리 단순, Paster 경험 재활용 가능 |
| D-005 | 내부용 선배포 | 퀄리티 검증 후 유료 공개 전환 |
| D-006 | HUD 기본은 볼륨 스타일, 선택 가능 | 친숙함 + 차별화 욕구 양립 |

---

*본 문서는 살아있는 문서입니다. 구현 중 발견되는 사항은 수시로 반영합니다.*
