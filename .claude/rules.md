# Project Context

## Overview

- iOS 26 SwiftUI app — internal name `BluetoothTesting`, product name **WatchDog**
- Companion app for the WatchDog BLE security/motion-tracker hardware
- Targets iPhone and iPad, minimum deployment iOS 26
- Swift 6 with strict concurrency
- Forced dark mode (`.preferredColorScheme(.dark)` in `BluetoothTestingApp`)
- `Info.plist` is intentionally empty — keys are configured in the Xcode project's generated Info

## Architecture

- State is held in `@Observable` classes (Swift Observation framework). **No `ObservableObject`/`@Published`.**
- Most managers are **singletons** exposed via `.shared` (`BondManager`, `SettingsManager`, `MotionLogManager`, `NavigationStateManager`, `DeviceNameManager`, `DeviceIconManager`, `DeviceNotesManager`, `MotionDataRecorder`). They are referenced as `let` properties inside views — Observation tracks reads automatically.
- `BluetoothManager` is the one non-singleton; created as `@State` in `MainAppView` and passed down by reference to subviews.
- Persistence is **UserDefaults + JSON encoding**, not SwiftData. `@AppStorage` is used for simple flags (e.g. `hasSeenTutorial`).
- Top-level navigation is a paged `TabView` (`.tabViewStyle(.page)`), not `NavigationStack`. Pages: Add-device → one page per bonded device → About. `NavigationStateManager` persists which page was last shown.
- Modal flows (pairing, motion logs, battery diagnostic) are presented as full-screen overlays or sheets layered over the TabView.
- Views are not split into separate ViewModel files — view-local `@State` plus the shared `@Observable` managers do that job. Don't introduce a ViewModel layer unless asked.

## Bluetooth

- `BluetoothManager` is a `CBCentralManager` wrapper. Target service UUID is `0x183E`.
- All `@Observable` writes happen on the main thread. Delegate callbacks `DispatchQueue.main.async` before mutating state — preserve this pattern; do not write observed state from the BLE queue.
- Scanning model: `ensureScanning()` is the single idempotent entry point. **Never call `stopScan()`** as part of normal flows — the codebase deliberately keeps the scan alive across connect/disconnect to avoid past "scan died" bugs (see fix-summary header in `BluetoothManager.swift`).
- BLE protocol uses single-byte opcodes. Commands: `0xF0` request log count, `0xF1` request event, `0xF2` clear log, `0xF3` ack event, `0xFA` ping, `0xFB` reset device, `0xFC` drain mode. Responses: `0xE0`–`0xE3` motion-log responses; `0xFF` motion-alert marker. Status/telemetry packets start with the settings byte.
- Battery telemetry comes from a BQ27427 fuel gauge over a dedicated characteristic (`...4442` UUID). `BatteryDiagnostic` parses v2 (18 byte), v3 (30 byte), and v11 (51 byte) variants — keep all three supported when editing.

## 3D / Visuals

- `SceneView3D` (`UIViewRepresentable` over SceneKit) renders `WatchDogBTCase_Final.usdz` / `WatchDogBTCase_V2.usdz`. Caches loaded nodes and texture maps as static properties — don't break the cache when editing.
- `LEDAnimator` is a state machine that mirrors the firmware's LED logic. It is the source of truth for `outputColor` / `outputIntensity` consumed by `SceneView3D`. Don't drive the LED color from views directly.
- UIKit is used where SwiftUI doesn't fit: `UIImpactFeedbackGenerator` for haptics, `UIColor`/`UIViewRepresentable` for SceneKit. That's fine — only avoid UIKit for things SwiftUI handles natively.

## Code Style

- One type per file; group by feature (`Managers/`, `Models/`, `Views/`, `Views/Components/`, `App/`).
- New SwiftUI views must include a `#Preview` block.
- SF Symbols only for icons; reference by exact name (see `DeviceIcon` enum for the curated set).
- Naming: PascalCase types, camelCase properties.
- Prefer `async/await` over completion handlers when introducing new async work. Existing BLE code uses `Timer` + delegate callbacks — keep that pattern when editing it.

## Testing

- Use **Swift Testing** (`@Test`, `#expect`) — not XCTest.
- Test targets: `BluetoothTestingTests` and `BluetoothTestingUITests`.

## Build

- Xcode project: `BluetoothTesting.xcodeproj`, scheme `BluetoothTesting`.
- SPM only — no CocoaPods.
- Verify Apple API names against the docs before using them; do not invent symbols.
