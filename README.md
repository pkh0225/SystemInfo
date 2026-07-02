# SystemInfo

iOS 앱에서 CPU, 메모리, FPS, 발열 상태를 오버레이로 확인할 수 있는 Swift Package입니다.

https://github.com/pkh0225/SystemInfo/blob/main/screensshot.png

## 설치

```swift
dependencies: [
    .package(url: "https://github.com/pkh0225/SystemInfo.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SystemInfo", package: "SystemInfo"),
        ]
    ),
]
```

## 사용법

```swift
import SystemInfo

// 저장된 설정 복원
SystemInfoManager.shared.loadUserDefaults()

// 리포트 on/off
SystemInfoManager.shared.isResourceReport = true
SystemInfoManager.shared.isFpsReport = true
SystemInfoManager.shared.isThermalReport = true
```

## 테스트

### 단위 테스트

`Package.swift` 를 Xcode에서 연 뒤 `SystemInfoTests` 스킴으로 실행하거나:

```bash
xcodebuild test \
  -scheme SystemInfo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
```

### 데모 앱

수동 UI 테스트는 [Example/README.md](Example/README.md) 를 참고하세요.
