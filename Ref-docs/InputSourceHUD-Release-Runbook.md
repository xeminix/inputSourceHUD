# InputSourceHUD Release Runbook — InputSourceHUD 릴리즈 표준 절차

이 문서는 `inputsourcehud-release` skill과 같은 내용을 저장소용 Markdown으로 보관한 것이다. 릴리즈 절차를 바꾸면 `codex-skills/inputsourcehud-release/`와 이 문서를 함께 업데이트한다.

## 개요

InputSourceHUD 릴리즈는 다음 순서로 진행한다.

1. 현재 버전, 빌드 번호, Sparkle 설정, 릴리즈 저장소 상태를 점검한다.
2. 필요하면 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`을 올린다.
3. Release 앱을 빌드하고 서명을 확인한다.
4. DMG를 만들고 공증 후 스테이플한다.
5. Sparkle `appcast.xml`을 재생성한다.
6. GitHub release asset과 `xeminix_release` 저장소의 `appcast.xml`을 배포한다.
7. 최종 검증 후 마무리한다.

## 고정 경로와 값

- 앱 저장소 루트: 현재 `inputSourceHUD` 작업 디렉터리
- Xcode 프로젝트: `InputSourceHUD.xcodeproj`
- 버전 설정 파일: `InputSourceHUD.xcodeproj/project.pbxproj`
- Info.plist: `InputSourceHUD/Resources/Info.plist`
- 기본 DerivedData: `/tmp/InputSourceHUDDerivedData`
- 릴리즈 스테이징 디렉터리: `/tmp/inputsourcehud-release-signed-<version>`
- 릴리즈 저장소 로컬 클론: `/tmp/xeminix_release`
- appcast 파일 경로: `/tmp/xeminix_release/inputsourcehud/appcast.xml`
- GitHub release 저장소: `xeminix/xeminix_release`
- GitHub release tag 형식: `inputsourcehud-v<version>`
- 배포 아티팩트 파일명: `InputSourceHUD.dmg`
- Sparkle appcast URL: `https://raw.githubusercontent.com/xeminix/xeminix_release/main/inputsourcehud/appcast.xml`
- 권장 서명 ID: `Developer ID Application: YONGSUB LEE (XU8HS9JUTS)`
- Sparkle `generate_appcast`: `/tmp/InputSourceHUDDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast`

## 1. Preflight

skill의 preflight 스크립트를 먼저 실행한다.

```bash
codex-skills/inputsourcehud-release/scripts/release_preflight.sh
```

추가 확인이 필요하면 다음도 본다.

```bash
git status --short
git -C /tmp/xeminix_release status --short --branch
rg -n "MARKETING_VERSION|CURRENT_PROJECT_VERSION|SPARKLE_APPCAST_URL|SPARKLE_PUBLIC_ED_KEY" InputSourceHUD.xcodeproj/project.pbxproj
plutil -p InputSourceHUD/Resources/Info.plist
```

`Info.plist`는 아래처럼 빌드 설정 참조를 유지해야 한다.

- `CFBundleShortVersionString` -> `$(MARKETING_VERSION)`
- `CFBundleVersion` -> `$(CURRENT_PROJECT_VERSION)`
- `SUFeedURL` -> `$(SPARKLE_APPCAST_URL)`
- `SUPublicEDKey` -> `$(SPARKLE_PUBLIC_ED_KEY)`

## 2. 버전과 빌드 번호 갱신

릴리즈가 새 버전이면 `InputSourceHUD.xcodeproj/project.pbxproj`에서 다음 값을 올린다.

- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`

값을 바꾼 뒤 `Info.plist`에 리터럴 버전 문자열을 박아 넣지 않는다. 항상 build setting 참조를 유지한다.

## 3. Release 빌드

```bash
xcodebuild -resolvePackageDependencies -project InputSourceHUD.xcodeproj
xcodebuild -project InputSourceHUD.xcodeproj -scheme InputSourceHUD -configuration Release -derivedDataPath /tmp/InputSourceHUDDerivedData build
codesign --verify --deep --strict --verbose=4 /tmp/InputSourceHUDDerivedData/Build/Products/Release/InputSourceHUD.app
```

빌드 후 앱 서명이 기대한 Developer ID가 아니거나 재서명이 필요하면:

```bash
codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: YONGSUB LEE (XU8HS9JUTS)" /tmp/InputSourceHUDDerivedData/Build/Products/Release/InputSourceHUD.app
codesign --verify --deep --strict --verbose=4 /tmp/InputSourceHUDDerivedData/Build/Products/Release/InputSourceHUD.app
```

## 4. DMG 생성, 공증, 스테이플

먼저 변수부터 정한다.

```bash
VERSION="1.1.1"
BUILD="111"
STAGING_DIR="/tmp/inputsourcehud-release-signed-${VERSION}"
APP_PATH="/tmp/InputSourceHUDDerivedData/Build/Products/Release/InputSourceHUD.app"
DMG_PATH="${STAGING_DIR}/InputSourceHUD.dmg"
```

그 다음 스테이징 앱과 DMG를 만든다.

```bash
mkdir -p "$STAGING_DIR"
rm -rf "${STAGING_DIR}/InputSourceHUD.app"
cp -R "$APP_PATH" "${STAGING_DIR}/InputSourceHUD.app"
hdiutil create -volname "InputSourceHUD" -srcfolder "${STAGING_DIR}/InputSourceHUD.app" -ov -format UDZO "$DMG_PATH"
```

공증과 스테이플:

```bash
xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --team-id XU8HS9JUTS --password "$APP_PASSWORD" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv "$DMG_PATH"
```

메모:

- 이 프로젝트에서는 DMG 자체 코드서명보다 공증 완료와 `stapler validate` 통과가 더 중요하다.
- 실제 인증서 조회는 Codex 샌드박스에서 제한될 수 있으니, 필요하면 일반 터미널에서도 확인한다.

## 5. Sparkle appcast 재생성

릴리즈 저장소를 직접 오염시키지 않도록 임시 디렉터리에서 appcast를 생성한 뒤 XML만 복사한다.

```bash
RELEASE_TAG="inputsourcehud-v${VERSION}"
APPCAST_WORK_DIR="${STAGING_DIR}/appcast"
mkdir -p "$APPCAST_WORK_DIR"
cp "$DMG_PATH" "${APPCAST_WORK_DIR}/InputSourceHUD.dmg"
cp /tmp/xeminix_release/inputsourcehud/appcast.xml "${APPCAST_WORK_DIR}/appcast.xml"
```

릴리즈 노트는 DMG와 같은 basename으로 둔다.

파일 경로:

```text
${APPCAST_WORK_DIR}/InputSourceHUD.md
```

예시:

```markdown
# InputSourceHUD 1.1.1

- Sparkle update path improvements
- HUD behavior fixes
- Multi-monitor stability improvements
```

appcast 생성:

```bash
/tmp/InputSourceHUDDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/xeminix/xeminix_release/releases/download/${RELEASE_TAG}" \
  --embed-release-notes \
  --link "https://github.com/xeminix/inputSourceHUD" \
  "$APPCAST_WORK_DIR"
```

생성 후 결과 XML만 릴리즈 저장소에 반영한다.

```bash
cp "${APPCAST_WORK_DIR}/appcast.xml" /tmp/xeminix_release/inputsourcehud/appcast.xml
```

`appcast.xml`이나 release note를 수동 수정했으면 `generate_appcast`를 다시 실행해 서명을 맞춘다.

## 6. GitHub release asset과 appcast 배포

먼저 릴리즈 저장소와 GitHub 인증 상태를 확인한다.

```bash
git -C /tmp/xeminix_release pull --ff-only
gh auth status -h github.com
gh release view "$RELEASE_TAG" -R xeminix/xeminix_release --json tagName,name,assets,url
```

tag가 이미 있으면 DMG를 업로드 또는 교체한다.

```bash
gh release upload "$RELEASE_TAG" "$DMG_PATH" -R xeminix/xeminix_release --clobber
```

그 다음 appcast만 커밋하고 푸시한다.

```bash
git -C /tmp/xeminix_release add inputsourcehud/appcast.xml
git -C /tmp/xeminix_release commit -m "Update InputSourceHUD ${VERSION} appcast after notarization"
git -C /tmp/xeminix_release push origin main
```

## 7. 최종 검증

릴리즈 마감 전 아래를 확인한다.

- `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`이 의도한 값인지
- `InputSourceHUD.dmg`가 공증되었고 `xcrun stapler validate`가 통과하는지
- `inputsourcehud/appcast.xml`이 `inputsourcehud-v<version>/InputSourceHUD.dmg`를 가리키는지
- appcast의 `sparkle:version`이 build 번호와 일치하는지
- 앱 저장소와 릴리즈 저장소에서 의도하지 않은 파일이 함께 바뀌지 않았는지

## 관련 파일

- `codex-skills/inputsourcehud-release/SKILL.md`
- `codex-skills/inputsourcehud-release/references/project-context.md`
- `codex-skills/inputsourcehud-release/references/release-workflow.md`
- `codex-skills/inputsourcehud-release/scripts/release_preflight.sh`
