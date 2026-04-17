> **⚠ Archive**: 이 문서는 초기 초안입니다. 최신 기획은 [InputSourceHUD-Plan.md](./InputSourceHUD-Plan.md)을 참조하세요.

# macOS Input Source Auto Switcher PRD

## 1. 제품 개요

### 목표
macOS에서 앱 전환 시 입력 소스를 자동으로 변경하여 사용자의 입력기 전환 불편을 제거한다.

### 핵심 컨셉
- 앱 전환 시 입력 소스 자동 변경
- 앱별 입력 소스 지정
- 미지정 앱은 default input source 적용
- 입력 변경 시 HUD 표시

---

## 2. 지원 환경

- macOS 15 이상
- Apple Silicon / Intel Mac
- 오프라인 동작 지원
- Menubar App (Dock 미표시)

---

## 3. 핵심 기능

### 3.1 앱 전환 기반 입력 소스 변경

#### 동작 흐름

1. 앱 전환 발생  
2. 현재 활성 앱 bundle id 확인  
3. 예외 앱 여부 체크  
4. 예외 앱이면 종료  
5. 앱별 설정 존재 여부 확인  
6. 설정 존재 → 해당 input source 적용  
7. 설정 없음 → default input source 적용  
8. 실제 변경 발생 시 HUD 표시  

#### 정책
- 앱 전환 시 1회 적용
- 앱 내부에서 사용자 변경은 허용

---

### 3.2 입력 소스 선택

- macOS 시스템 설정에서 활성화된 input source만 표시
- 해당 목록에서만 선택 가능

---

### 3.3 앱별 설정

#### 구조
BundleID → InputSourceID

#### 기능
- 현재 활성 앱 추가
- 앱 검색 기반 추가
- 앱별 input source 지정

---

### 3.4 Default Input Source

- 미지정 앱에 대해 항상 적용
- 앱 전환 시 강제 적용

---

### 3.5 예외 앱 정책

- 사용자 지정 예외 앱 리스트 지원
- 예외 앱은 입력 소스 변경 대상에서 제외

---

### 3.6 HUD (Input Source Overlay)

#### 표시 조건
- 입력 소스가 실제 변경된 경우에만 표시

#### 위치
- 마우스 커서가 위치한 모니터 중앙

#### 기본 스타일
- 반투명 다크 배경
- blur effect
- rounded corner
- 중앙 텍스트
- fade in/out 애니메이션

#### 표시 내용 옵션
- short name (예: A, 한, 英)
- full name (예: English, 한국어, 日本語)

#### 사용자 커스터마이징
- 표시 시간 (duration)
- fade in 시간
- fade out 시간
- 텍스트 스타일 (short / full)

#### 기본값
- duration: 1.0초
- fade in/out: 0.2~0.3초
- 텍스트: short name

#### 추가 기능
- Reset to Default 버튼 제공

---

### 3.7 Menubar App

- menubar icon 표시
- Dock 표시 없음
- 메뉴 기능:
  - 설정 열기
  - 앱 추가
  - 활성화/비활성화
  - 종료

---

### 3.8 Login 시 자동 실행

- 로그인 시 자동 실행 지원
- 실행 후 백그라운드 동작
- 권한 없을 경우 안내 UI 표시

---

### 3.9 설정 저장

- 로컬 저장 (UserDefaults 또는 파일)
- 네트워크 필요 없음

---

### 3.10 업데이트

- Sparkle 기반 OTA 업데이트

---

## 4. UI 구조

### Settings 화면

- Default Input Source 설정
- App List
- Exception App List
- HUD 설정
- Login at startup 설정
- Reset 버튼

---

### 앱 추가 UX

- 현재 활성 앱 추가
- 앱 검색 기능
- 최근 실행 앱 우선 표시

---

## 5. 비기능 요구사항

- 빠른 앱 전환에서도 안정 동작
- latency < 200ms 목표
- multi-monitor 지원
- race condition 방지

---

## 6. 예외 처리

- 입력 변경 실패 시 기존 상태 유지
- HUD spam 방지 (throttle)
- 최신 상태 기준 처리

---

# 개발 계획서

## 1. 아키텍처

App (Menubar)
- AppMonitorService
- InputSourceService
- HUDService
- SettingsService
- ExceptionService

---

## 2. 주요 컴포넌트

### AppMonitorService
- 앱 전환 감지
- NSWorkspace notification 사용
- debounce 처리

---

### InputSourceService
- 입력 소스 조회 및 변경
- Carbon API 사용

---

### HUDService
- overlay 표시
- multi-monitor 대응
- fade animation

---

### SettingsService
- 설정 저장/로드

#### JSON 구조 예시

{
  "defaultInputSource": "...",
  "appMappings": {
    "com.apple.dt.Xcode": "...",
    "com.jetbrains.intellij": "..."
  },
  "exceptions": [
    "com.apple.Terminal"
  ],
  "hud": {
    "duration": 1.0,
    "fadeIn": 0.2,
    "fadeOut": 0.2,
    "style": "short"
  }
}

---

### ExceptionService
- 예외 앱 필터링

---

## 3. 상태 처리 로직

onAppActivated(app):
    if app in exceptions:
        return

    targetInput =
        appMapping[app.bundleId] ??
        defaultInput

    if currentInput != targetInput:
        changeInput(targetInput)
        showHUD(targetInput)

---

## 4. 성능 전략

- debounce 적용
- cancelable task
- latest 상태 기준 처리

---

## 5. 빌드 및 배포

- Code Signing
- Notarization
- DMG 패키징
- Sparkle OTA

---

## 6. Todo (확장 기능)

- 앱별 last input 기억 모드
- HUD 커스터마이징 확장
- menubar 상태 표시 옵션
- 설정 import/export
- iCloud sync
- fullscreen 앱 예외 처리
- App Store 배포

---

## 7. 리스크

- Carbon API 의존성
- macOS 정책 변경 가능성
- 일부 앱 이벤트 타이밍 문제

---

## 결론

- macOS 생산성 향상 유틸리티
- lightweight menubar 앱
- offline-first 구조
- 확장 가능한 아키텍처
