# App Store Submission Readiness — Changes

Pass-through against the readiness prompt. Items marked **[Done]** are
landed; items marked **[Needs you]** require human/Xcode-UI/external action
that I deliberately didn't attempt autonomously.

## Done

### Section 1 — Info.plist build settings (`project.pbxproj`)
Project uses `GENERATE_INFOPLIST_FILE = YES`, so all keys are driven by
`INFOPLIST_KEY_*` build settings (the `Info.plist` source file is intentionally
empty). Added/updated in **both** Debug and Release configs:

| Key | Value |
|---|---|
| `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` | WatchDog-specific copy (replaces the generic prior message). |
| `INFOPLIST_KEY_NSBluetoothPeripheralUsageDescription` | Same WatchDog-specific copy (defensive — covers older iOS variants). |
| `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` | `NO` — exempts you from annual U.S. encryption export filing. |
| `INFOPLIST_KEY_LSApplicationCategoryType` | `public.app-category.utilities`. |
| `INFOPLIST_KEY_UIRequiredDeviceCapabilities` | `bluetooth-le` — gates installs to BLE-capable devices. |

`UIBackgroundModes` remains absent → background-BLE is dropped, matching the
prompt's recommended path. `INFOPLIST_KEY_CFBundleDisplayName = WatchDog` was
already in place. `IPHONEOS_DEPLOYMENT_TARGET = 18.5` (Xcode auto-fills
`MinimumOSVersion` from this). Pre-existing
`INFOPLIST_KEY_UILaunchScreen_Generation = YES` and the orientation keys are
unchanged.

### Section 2 — Privacy manifest
- Added `BluetoothTesting/PrivacyInfo.xcprivacy` with:
  - `NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`, empty `NSPrivacyCollectedDataTypes`.
  - `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` (single-app reads/writes — covers `BondManager`, `AppPreferences`, `DeviceNameManager`, `LocalizationManager`, `NavigationStateManager`, `SettingsManager`).
  - `NSPrivacyAccessedAPICategorySystemBootTime` reason `35F9.1` — covers `CACurrentMediaTime()` in `Views/Components/SceneView3D.swift` (used for the wobble timing). This was the only required-reason API beyond UserDefaults; I greppped for `creationDate`, `contentModificationDate`, `systemUptime`, `mach_absolute_time`, `volumeAvailable*`, `getattrlist`, `activeInputModes` and only `CACurrentMediaTime` matched.
- File lives inside the project's `PBXFileSystemSynchronizedRootGroup`, so target membership is automatic — no pbxproj plumbing needed.

### Section 3 — Debug surfaces hidden from Release
- `Managers/Log.swift` — every `print(…)` call is wrapped in `#if DEBUG`. The static state (`tagColumnCells`, `headerPrinted`, `lock`) is also `#if DEBUG`-gated since nothing references it in Release. Convenience entry points (`Log.info`, `Log.ok`, `Log.warn`, `Log.err`, `Log.tx`, `Log.rx`, `Log.section`, `Log.endSection`, `Log.banner`) keep their public signatures so call sites compile unchanged — they just no-op in Release.
- `Views/DevicePageView.swift` — the entire "BATTERY STATS / ACCEL (g)" debug overlay block (the `if isDeviceConnected && settingsManager.debugModeEnabled { … }` from the left-side `VStack`) is wrapped in `#if DEBUG`. Even if a stale UserDefaults value flips `debugModeEnabled` to `true` in a Release build, the panel does not render.
- `Views/DevicePageView.swift` — the 10-tap-on-battery-icon dev-mode unlock gesture body is wrapped in `#if DEBUG`. In Release, the gesture handler does nothing, so `devModeUnlocked` can never flip to `true` from the UI.
- `Views/Components/WatchDogSettingsView.swift` — the `if settingsManager.devModeUnlocked { debugSection }` block (which exposes the "Debug Tools" section: Live Orientation, Debug Mode, Data Logging, Show Tutorial, Reset Device) is wrapped in `#if DEBUG`.
- Project file membership exceptions added so these never ship inside the `.app`:
  - `APP_STORE_READINESS_PROMPT.md`
  - `FW_DIAG_VERIFICATION_PROMPT.md`
  - `FW_POWER_OPT_PROMPT.md`
  - `fix_settings_transition_prompt.md`
  - `WatchDogBT_Power_Optimization_Research.docx`

  All three `.usdz` files (`WatchDogBTCase_Final.usdz`, `WatchDogBTCase_V2.usdz`, `WatchDogBTPCB.usdz`) are **kept** — every one is referenced by `SceneView3D` / `DevicePageView` / `Motion3DView`.

### Section 4 — App icon
- All three icons under `Assets.xcassets/AppIcon.appiconset/` (default, dark, tinted) are 1024×1024 with `hasAlpha: no` (verified via `sips`). No double-mask risk.
- `Contents.json` uses the modern single-1024-master pattern; Xcode generates the smaller sizes at build time. iOS 18 dark / tinted variants are present.

### Section 7 — Background BLE: dropped
- Confirmed `UIBackgroundModes` is absent from both `project.pbxproj` and `Info.plist`. The 5-second background-disconnect timer in `App/MainAppView.swift` (gated on `AppPreferences.disconnectOnBackground`, default `true`) is the only background behaviour. No `CBCentralManager` state-restoration plumbing is needed.

### Section 8 — User-facing strings
- Grep across `Views/`, `App/`, and `LocalizationManager.swift` for `Lorem`, `TODO`, `FIXME`, `placeholder`, `TBD`: only one match — `Views/DevicePageView.swift` line 324, the comment `// Device is NOT in range — show placeholder`, which is a code comment, not user-visible. Clean.
- File-header `── FIX SUMMARY ──` blocks in `MainAppView.swift` are comments, not shipped.

### Section 9 — Localization parity
- `LocalizationManager.swift` has 6 languages: English, Spanish, Dutch, French, Japanese, Portuguese. Each language dictionary has the same number (57) of key-defining lines — confirmed via `awk`/`grep` per-section count. `LocKey` is a Swift enum, so missing keys at call sites would be a compile error, not a runtime fall-through to a raw enum case.
- `t(key)` falls back to `.english` if a translation is somehow missing; the `?? ""` default also prevents reflection-style leaks.

### App version bump (per `CLAUDE.md`)
- One new dev commit `65d939c` since the previous reconcile at `eb7c109`.
- Bumped `AppVersion.v2` from `44` → `45` in `BluetoothTesting/AppVersion.swift`.
- Updated CLAUDE.md "Current" line to `V1.11.45` and reconciled-sha to `65d939c`.

---

## Needs you (cannot be done autonomously / out of code scope)

### Section 0 — Project rename to `WatchDog_iOS`
Skipped intentionally. Xcode's "Rename Project Content Items" GUI rewrites
`project.pbxproj`, the scheme, build-config dictionaries, and the on-disk
folder atomically. Doing this through raw file edits is high-risk —
mismatching even one reference can corrupt the project. Recommended path:

1. Open the project in Xcode → click the project node in the left sidebar → click the project name → hit `Enter` → type `WatchDog_iOS` → confirm "Rename Project Content Items".
2. Manually rename the `BluetoothTestingApp` struct → `WatchDogApp` and the file `BluetoothTestingApp.swift` → `WatchDogApp.swift`. Update the file's header comment.
3. Sweep the `.swift` files for `BluetoothTesting` strings in header comments (find/replace).
4. Build settings to update by hand (target → Build Settings):
   - `PRODUCT_BUNDLE_IDENTIFIER`: `Sebkabob.BluetoothTesting` → final reverse-DNS (e.g. `com.<yourCompany>.watchdog`). **Required** before submission — App Store Connect won't accept "BluetoothTesting" as a bundle id.
   - `INFOPLIST_KEY_CFBundleName`: not currently set; if you want it explicit, add `WatchDog_iOS`. Xcode otherwise derives this from `PRODUCT_NAME`.
5. Bump `MARKETING_VERSION` from `1.0` to whatever you list in App Store Connect (e.g. `1.0.0`). The internal `V1.11.45` in `AppVersion.swift` is independent telemetry — it stays as-is.

### Section 5 — Privacy policy
Privacy policy page is not in the codebase. You need to:
1. Draft a policy mirroring the wording in Section 5 of the prompt (covers: nothing leaves device, BLE only used for the case, no analytics, no children's data, contact email).
2. Host it under HTTPS at a stable URL (e.g. `https://watchdog.app/privacy`).
3. Paste the URL into App Store Connect → App Information → Privacy Policy URL, **and** select "Data Not Collected" in App Privacy → Data Types.

### Section 6 — Hardware-accessory survival kit
- A **demo mode** is already wired up in code (`Models/DemoSession.swift`, `Managers/SettingsManager.swift::enterDemoMode`, `MainAppView.swift::enterDemoMode`), with the entry point being the "No device? Try demo" tile on the add-watchdog screen. This satisfies the prompt's "single most effective change" — reviewer can hit it without hardware.
- You still need to:
  - Record a ≤60s walkthrough video (pairing → device page → 3D model → motion log → settings → unpair) and host it (unlisted YouTube/Vimeo or hosted mp4).
  - Write App Review notes that point reviewer at the demo tile and the video URL. Optionally offer to ship a review unit via [Apple's review-attachment form](https://developer.apple.com/contact/app-store/review-attachment/).

### Section 10 — App Store Connect metadata
Out of code scope. Have ready before you press Submit: app name, subtitle, promotional text, description, keywords, support URL, marketing URL (optional), privacy policy URL (Section 5), category (Utilities), age rating questionnaire, screenshots per supported size, optional preview video, App Review notes (Section 6).

### Section 11 — Pre-flight build
Once Section 0 is done, run from the Xcode project's parent directory:

```bash
xcodebuild clean -scheme WatchDog_iOS
xcodebuild archive \
  -scheme WatchDog_iOS \
  -archivePath build/WatchDog_iOS.xcarchive \
  -destination 'generic/platform=iOS'
plutil -p build/WatchDog_iOS.xcarchive/Products/Applications/WatchDog_iOS.app/Info.plist
find build/WatchDog_iOS.xcarchive -name "PrivacyInfo.xcprivacy"
```

Expect:
- `CFBundleDisplayName == "WatchDog"`
- `NSBluetoothAlwaysUsageDescription` present and WatchDog-specific
- `ITSAppUsesNonExemptEncryption == false`
- `bluetooth-le` in `UIRequiredDeviceCapabilities`
- exactly one `PrivacyInfo.xcprivacy` inside the `.app` bundle

Then validate via Organizer → "Validate App" before "Distribute App".

### Notes on the data-model and BLE manager
Per the prompt's Section 13, `BluetoothManager`, `BondedDevice`, `BluetoothDevice`, `MotionEvent`, etc. were not touched. No new abstractions or refactors introduced.

---

## File diff summary

```
modified:  BluetoothTesting.xcodeproj/project.pbxproj
modified:  BluetoothTesting/AppVersion.swift                       (V1.11.44 → V1.11.45)
modified:  BluetoothTesting/Managers/Log.swift                     (#if DEBUG gating)
modified:  BluetoothTesting/Views/DevicePageView.swift             (#if DEBUG gating)
modified:  BluetoothTesting/Views/Components/WatchDogSettingsView.swift  (#if DEBUG gating)
modified:  CLAUDE.md                                               (version line)
new:       BluetoothTesting/PrivacyInfo.xcprivacy
new:       CHANGES.md
```
