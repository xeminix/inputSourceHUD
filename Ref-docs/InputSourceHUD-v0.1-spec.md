# InputSourceHUD v0.1 확정 설계

> 앱 전환 기반 입력 소스 자동 전환 + 경량 HUD menubar app

**작성일**: 2026-04-16  
**문서 버전**: 1.0  
**상태**: v0.1 구현 기준 확정안  
**리포지토리**: `xeminix/inputSourceHUD`  
**Bundle ID**: `com.codequa.inputSourceHUD`

---

## 1. 문서 목적

이 문서는 v0.1 구현 기준으로 아래 두 문서의 충돌 사항을 정리해 하나의 스펙으로 고정한다.

- `Ref-docs/input-source-switcher-prd.md`
- `Ref-docs/InputSourceHUD-Plan.md`

위 두 문서는 참고 문서로 유지하고, **v0.1 구현 시에는 본 문서를 우선 적용**한다.

---

## 2. 제품 정의

### 2.1 한 줄 설명
macOS에서 앱 전환 시 지정된 입력 소스로 자동 전환하고, 실제 전환 결과를 HUD로 알려주는 menubar 유틸리티.

### 2.2 해결하려는 문제
- 개발 도구와 메신저를 오갈 때 한/영 입력 상태가 문맥과 맞지 않아 반복 전환이 필요하다.
- macOS의 앱별 입력 소스 기억 동작은 사용자가 기대하는 수준으로 일관되지 않다.

### 2.3 타겟 사용자
- 한/영 입력 전환이 잦은 macOS 사용자
- 개발자, 번역가, 이중 언어 사용 직장인

### 2.4 지원 환경
- macOS 15 이상
- Apple Silicon / Intel Universal Binary
- 오프라인 동작
- Menubar App (`LSUIElement = YES`)

---

## 3. v0.1 제품 범위

### 3.1 포함 범위
- 앱 전환 감지 기반 자동 입력 소스 전환
- 전역 기본 입력 소스 설정
- 앱별 규칙 설정
- 입력 소스 목록 조회 및 선택
- 성공 전환 / Secure Input 차단 시 HUD 표시
- menubar 상태 표시
- 로컬 설정 저장
- 설정 창에서 핵심 옵션 수정
- 로그인 시 자동 실행

### 3.2 제외 범위
다음 항목은 v0.1에서 제외하고 후속 버전으로 미룬다.

- 화이트리스트 / 블랙리스트 모드
- 별도 exception list UI
- HUD 스타일 3종
- 앱별 HUD ON/OFF
- HUD 세부 애니메이션 커스터마이징
- 글로벌 단축키
- 설정 Export / Import
- Sparkle OTA 업데이트
- 다국어 로컬라이제이션
- iCloud 동기화
- 브라우저 URL 단위 규칙
- Shortcuts.app 통합
- 라이선스 / 결제

### 3.3 범위 축소 이유
- v0.1의 핵심 가치는 "정확한 자동 전환"이다.
- 정책 모델과 HUD 옵션을 과도하게 넓히면 코어 안정성 검증이 늦어진다.
- `ignore` 규칙만으로도 기존 exception list의 핵심 요구를 충족할 수 있다.

---

## 4. 최종 동작 사양

### 4.1 이벤트 흐름

1. 사용자가 포그라운드 앱을 전환한다.
2. `NSWorkspace.didActivateApplicationNotification`을 수신한다.
3. 100ms debounce를 적용하고, 최신 앱 전환 이벤트만 처리한다.
4. 앱의 `bundleIdentifier`를 읽는다.
5. 전역 `enabled`가 `false`이면 아무 작업도 하지 않는다.
6. 앱별 규칙을 조회한다.
7. 규칙에 따라 대상 입력 소스를 결정한다.
8. 현재 입력 소스와 대상 입력 소스가 같으면 아무 작업도 하지 않는다.
9. Secure Input이 활성화되어 있으면 실제 전환은 하지 않고 차단 HUD만 표시한다.
10. Secure Input이 아니면 `TISSelectInputSource`로 전환을 시도한다.
11. 전환 성공 시 성공 HUD를 표시한다.
12. 전환 실패 시 상태는 유지하고 로그만 남긴다.

### 4.2 규칙 모델

v0.1의 앱별 규칙은 아래 세 가지 중 하나다.

- `force`: 특정 입력 소스로 강제 전환
- `useGlobalDefault`: 앱 전환 시 전역 기본 입력 소스로 전환
- `ignore`: 해당 앱에서는 아무 작업도 하지 않고 macOS 기본 동작 유지

### 4.3 정책 결정 규칙

- 앱별 규칙이 있으면 해당 규칙을 따른다.
- 앱별 규칙이 없으면 `useGlobalDefault`로 간주한다.
- 전역 기본 입력 소스가 비어 있으면 자동 전환 기능은 비활성 상태로 간주하고 로그만 남긴다.
- 입력 소스 선택 UI에는 macOS 시스템 설정에 이미 등록된 입력 소스만 노출한다.

### 4.4 사용자 입력 변경 허용

- 앱 전환 시에는 1회만 규칙을 적용한다.
- 같은 앱 안에서 사용자가 직접 입력 소스를 바꾸는 것은 허용한다.
- 사용자가 같은 앱 안에서 바꾼 입력 소스를 다시 덮어쓰지 않는다.

### 4.5 HUD 표시 규칙

HUD는 아래 두 경우에만 표시한다.

- 입력 소스가 실제로 변경된 경우
- Secure Input 때문에 변경이 차단된 경우

HUD를 표시하지 않는 경우:

- 현재 입력 소스와 대상 입력 소스가 같은 경우
- 앱 규칙이 `ignore`인 경우
- 전역 기능이 꺼져 있는 경우
- 입력 소스 전환 실패한 경우

### 4.6 Secure Input 처리

- `IsSecureEventInputEnabled()`로 상태를 확인한다.
- Secure Input이 켜져 있으면 실제 전환은 시도하지 않는다.
- HUD 문구는 "Secure Input active" 성격의 차단 안내를 사용한다.
- 해당 상황은 `OSLog`에 기록한다.

### 4.7 HUD 사양

v0.1의 HUD는 단일 스타일만 제공한다.

- 스타일: volume HUD 계열 반투명 패널
- 구현: `NSPanel` + `nonactivatingPanel`
- 위치: 마우스 커서가 있는 모니터 중앙
- 내용: 앱 아이콘, 앱 이름, 대상 입력 소스 표시명
- 지속 시간 기본값: 1.0초
- 사용자 설정 가능 범위: 0.5초 ~ 2.0초
- 애니메이션: 짧은 fade in / fade out
- 포커스를 훔치지 않아야 한다

### 4.8 Menubar 사양

- Dock 및 App Switcher에는 노출하지 않는다.
- 상태 아이콘에는 현재 입력 소스 약어를 표시한다.
- 메뉴 항목:
  - Enable / Disable
  - Open Settings
  - Add Rule for Current App
  - Quit

---

## 5. 설정 UI 확정안

### 5.1 Settings 창 탭
v0.1에서는 탭을 최소 3개로 제한한다.

- `General`
- `Apps`
- `HUD`

### 5.2 General 탭
- 전역 활성화 ON/OFF
- 전역 기본 입력 소스 선택
- Launch at Login ON/OFF

### 5.3 Apps 탭
- 등록된 앱 규칙 목록
- 현재 활성 앱 빠른 추가
- 앱 검색 또는 앱 선택 기반 추가
- 앱별 규칙 선택:
  - Force Specific Input Source
  - Use Global Default
  - Ignore

### 5.4 HUD 탭
- HUD ON/OFF
- HUD 표시 시간 조절
- 미리보기 버튼

### 5.5 제외한 UI
v0.1에서는 아래 UI를 만들지 않는다.

- Exception App List 전용 화면
- White/Blacklist 모드 전환
- Shortcuts 탭
- Advanced 탭

---

## 6. 데이터 모델 확정안

### 6.1 설정 스키마

```json
{
  "schemaVersion": 1,
  "global": {
    "enabled": true,
    "defaultInputSourceId": "com.apple.keylayout.ABC",
    "debounceMillis": 100,
    "launchAtLogin": false
  },
  "hud": {
    "enabled": true,
    "durationSeconds": 1.0
  },
  "apps": [
    {
      "bundleId": "com.apple.dt.Xcode",
      "displayName": "Xcode",
      "policy": "force",
      "inputSourceId": "com.apple.keylayout.ABC"
    },
    {
      "bundleId": "com.tinyspeck.slackmacgap",
      "displayName": "Slack",
      "policy": "force",
      "inputSourceId": "com.apple.inputmethod.Korean.2SetKorean"
    },
    {
      "bundleId": "com.apple.Terminal",
      "displayName": "Terminal",
      "policy": "ignore"
    }
  ]
}
```

### 6.2 저장 방식
- 기본 저장소는 `UserDefaults`
- 설정 모델은 `Codable`
- 향후 Export / Import를 위해 스키마 버전 필드를 유지한다

### 6.3 입력 소스 모델

```swift
struct InputSource: Identifiable, Codable, Hashable {
    let id: String
    let localizedName: String
    let shortLabel: String
}
```

### 6.4 앱 규칙 모델

```swift
enum AppPolicy: String, Codable {
    case force
    case useGlobalDefault
    case ignore
}

struct AppRule: Identifiable, Codable, Hashable {
    let bundleId: String
    var displayName: String
    var policy: AppPolicy
    var inputSourceId: String?
}
```

---

## 7. 기술 아키텍처 확정안

### 7.1 사용 기술
- SwiftUI
- AppKit
- Carbon Text Input Source API
- `OSLog`
- `SMAppService`

### 7.2 모듈 구조

```text
InputSourceHUD/
├── App/
│   ├── InputSourceHUDApp.swift
│   └── AppEnvironment.swift
├── Core/
│   ├── InputSource/
│   │   ├── InputSource.swift
│   │   ├── InputSourceManager.swift
│   │   └── InputSourceChangeObserver.swift
│   ├── AppSwitching/
│   │   ├── AppSwitchObserver.swift
│   │   └── AppSwitchCoordinator.swift
│   ├── Policy/
│   │   ├── AppPolicy.swift
│   │   └── PolicyStore.swift
│   └── SecureInput/
│       └── SecureInputDetector.swift
├── Features/
│   ├── HUD/
│   │   ├── HUDWindow.swift
│   │   ├── HUDWindowController.swift
│   │   ├── HUDContentView.swift
│   │   └── ScreenLocator.swift
│   ├── MenuBar/
│   │   ├── MenuBarController.swift
│   │   └── MenuBarIconRenderer.swift
│   └── Settings/
│       ├── SettingsWindow.swift
│       ├── GeneralTab.swift
│       ├── AppsTab.swift
│       └── HUDTab.swift
├── Infrastructure/
│   ├── Storage/
│   │   └── SettingsStore.swift
│   └── Logging/
│       └── Log.swift
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

### 7.3 코디네이터 책임
`AppSwitchCoordinator`는 아래 책임만 가진다.

- 이벤트 직렬화
- 최신 앱 전환 기준 처리
- 정책 해석
- Secure Input 체크
- 입력 소스 전환 시도
- HUD 표시 조건 판단
- 로그 기록

UI와 저장소 세부 구현은 코디네이터 밖으로 분리한다.

---

## 8. 개발 순서 확정안

### Phase 0. 기술 검증 스파이크
목표: 코어 기술 리스크를 구현 전에 제거한다.

- `TISCopyInputSourceList`로 활성 입력 소스 목록 조회
- `TISCopyCurrentKeyboardInputSource`로 현재 입력 소스 확인
- `TISSelectInputSource`로 ABC / 한국어 전환 검증
- `NSWorkspace.didActivateApplicationNotification` 수신 검증
- `IsSecureEventInputEnabled()` 검증
- 전체화면 앱 1개, 일반 앱 2개에서 기본 이벤트 확인

**Go / No-Go 기준**
- 최소 2개 입력 소스 전환이 안정적으로 동작해야 한다
- 앱 전환 이벤트가 의도대로 들어와야 한다
- Secure Input 차단 상태를 구분할 수 있어야 한다

### Phase 1. 앱 쉘 + 코어 전환
- Menubar App 생성
- `InputSourceManager` 구현
- `AppSwitchObserver` + debounce 구현
- `PolicyStore` 인메모리 버전 구현
- `AppSwitchCoordinator` 연결
- 로그로 동작 확인

### Phase 2. HUD
- `NSPanel` 기반 HUD 구현
- 마우스 기준 모니터 탐색
- 성공 / Secure Input 차단 HUD 표시
- 포커스 비활성 검증

### Phase 3. 설정 저장 + Settings UI
- `UserDefaults` 기반 `SettingsStore`
- General / Apps / HUD 탭 구현
- 앱 규칙 편집 UI 구현
- 기본 설정 저장 및 복원

### Phase 4. 운영 편의 기능
- menubar 현재 입력 소스 표시
- Add Rule for Current App
- Launch at Login
- 안정화 및 QA

---

## 9. 비기능 요구사항

- 앱 전환 후 처리 목표 지연: 200ms 이내
- race condition 없이 최신 상태 기준 처리
- 빠른 앱 전환에서도 중복 HUD가 과도하게 누적되지 않아야 함
- 멀티 모니터에서 잘못된 화면에 HUD가 표시되지 않아야 함
- 입력 소스 전환 실패 시 사용자 포커스를 훔치지 않아야 함

---

## 10. QA 기준

### 10.1 필수 테스트 앱
- Xcode
- Terminal
- Safari
- Slack
- 카카오톡 또는 다른 메신저 1개

### 10.2 필수 시나리오
- 영어 고정 앱 → 한글 고정 앱 전환
- 한글 고정 앱 → 영어 고정 앱 전환
- `ignore` 앱 진입 시 전환이 발생하지 않는지 확인
- 같은 앱 내부에서 수동 입력 변경 후 유지되는지 확인
- Secure Input 활성 앱에서 차단 HUD가 뜨는지 확인
- 멀티 모니터에서 커서 위치 기준으로 HUD가 뜨는지 확인
- 전체화면 앱 전환 시 오동작 여부 확인

---

## 11. v0.1 성공 기준

- 5개 이상의 실제 앱에서 앱별 입력 소스 전환이 안정적으로 동작한다
- 성공 전환과 Secure Input 차단을 사용자가 HUD로 구분할 수 있다
- menubar에서 현재 입력 소스 상태를 확인할 수 있다
- 재실행 후 설정이 유지된다
- 30분 이상 사용 중 크래시가 없다

---

## 12. 후속 버전 후보

v0.1 이후 우선순위 후보:

- HUD 스타일 확장
- 앱별 HUD 설정
- 글로벌 단축키
- Export / Import
- Sparkle 업데이트
- 한/영 로컬라이제이션
- White/Blacklist 모드
- iCloud 동기화

---

## 13. 최종 결정 요약

- 정책 모델은 `force / useGlobalDefault / ignore` 3종으로 고정한다.
- 별도 exception list와 whitelist/blacklist는 v0.1에서 제거한다.
- HUD는 단일 스타일만 제공한다.
- HUD는 성공 전환과 Secure Input 차단 상황에서만 표시한다.
- v0.1의 우선순위는 커스터마이징보다 전환 안정성이다.
- Sparkle, Export / Import, 글로벌 단축키는 v0.1 범위에서 제외한다.

---

*본 문서는 v0.1 구현 기준 문서이며, 이후 기능 확장은 새 버전 문서에서 다룬다.*
