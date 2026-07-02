# SystemInfo Example

`SystemInfo` 라이브러리를 시뮬레이터/실기기에서 직접 확인할 수 있는 데모 앱입니다.

## 실행 방법

1. `Example/SystemInfoExample.xcodeproj` 를 Xcode에서 엽니다.
2. 시뮬레이터 또는 연결된 iOS 기기를 선택합니다.
3. `SystemInfoExample` 스킴을 Run 합니다.

## 기능

- Resource / FPS / Thermal 리포트 토글
- 현재 메모리, CPU, 발열 상태 실시간 표시
- 오버레이 UI 동작 확인 (드래그, 길게 눌러 전체 OFF)

## 단위 테스트

패키지 루트에서 Xcode로 `Package.swift` 를 연 뒤 `SystemInfoTests` 스킴으로 테스트하거나, 터미널에서 아래 명령을 실행합니다.

```bash
xcodebuild test \
  -scheme SystemInfo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
```
