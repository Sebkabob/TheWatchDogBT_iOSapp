# App Store Submission Readiness — Fix-It Prompt

> **Role:** You are a senior iOS engineer responsible for taking the project from its current state to a state where it can be submitted to App Store Connect and pass App Review on the first try.
>
> **Working tree:** `/Users/sebkabob/Desktop/BluetoothTesting/BluetoothTesting`
>
> **Source language:** Swift / SwiftUI, deployment target iOS 17+ (uses `@Observable`, `.scenePhase`, etc.). CoreBluetooth is the only Apple framework that triggers privacy review.
>
> **Constraint:** Do **not** introduce third-party SDKs. Do **not** add network calls, analytics, or tracking. Keep the app fully on-device.
>
> **Verification:** After every change, build the project (`xcodebuild -scheme WatchDog_iOS -destination 'generic/platform=iOS' build`) and confirm zero warnings related to your changes. After all changes, run a clean build and an Archive build.

---

## Context — what this app is

A SwiftUI iOS companion app for the **WatchDog** Bluetooth case (a hardware accessory). It scans for, bonds with, and exchanges BLE messages with WatchDog devices; renders a 3D model (USDZ); records motion events; and stores a per-iPhone "loyalty token" in Keychain that the WatchDog hardware reads back. There is **no** server, **no** account system, **no** in-app purchases, **no** advertising, **no** third-party SDK. Local persistence is `UserDefaults` + Keychain only.

---

## Section 0 — Rename the project to `WatchDog_iOS`

The Xcode project, scheme, target, source folder, and bundle display must all be renamed. The on-device app name shown to users should be **"WatchDog"** (no underscore, no "iOS"). The Xcode product / scheme / repo folder uses `WatchDog_iOS`.

### Required renames

| Layer | Old | New |
|---|---|---|
| Repo / source folder | `BluetoothTesting` | `WatchDog_iOS` |
| Xcode project | `BluetoothTesting.xcodeproj` | `WatchDog_iOS.xcodeproj` |
| Xcode target / scheme | `BluetoothTesting` | `WatchDog_iOS` |
| `@main` struct | `BluetoothTestingApp` | `WatchDogApp` |
| Source file | `BluetoothTestingApp.swift` | `WatchDogApp.swift` |
| `PRODUCT_NAME` build setting | `BluetoothTesting` | `WatchDog_iOS` |
| `PRODUCT_BUNDLE_IDENTIFIER` | (current dev id) | `com.<yourCompany>.watchdog` (final reverse-DNS, lowercase, no `test`/`testing`/`debug`) |
| `CFBundleDisplayName` (user-facing app name) | "BluetoothTesting" | **"WatchDog"** |
| `INFOPLIST_KEY_CFBundleDisplayName` | "BluetoothTesting" | **"WatchDog"** |
| File header comments referencing "BluetoothTesting" | as-is | "WatchDog_iOS" |

### Steps

1. In Xcode: select the project in the navigator → rename → "Rename Project Content Items" → confirm. Xcode will rewrite `project.pbxproj`, the scheme, and the on-disk folder.
2. Manually rename the `BluetoothTestingApp` struct to `WatchDogApp` and rename `BluetoothTestingApp.swift` → `WatchDogApp.swift`. Update the file's header block comment.
3. Sweep all `.swift` source files for the literal string `BluetoothTesting` in header comments and docstrings; replace with `WatchDog_iOS`.
4. In **Build Settings** (target → Build Settings → All → Combined):
   - `PRODUCT_NAME` → `WatchDog_iOS`
   - `PRODUCT_BUNDLE_IDENTIFIER` → final production reverse-DNS id
   - `INFOPLIST_KEY_CFBundleDisplayName` → `WatchDog`
   - `INFOPLIST_KEY_CFBundleName` → `WatchDog_iOS`
5. If the repo has a `.git` directory, run `git mv` rather than plain `mv` so history is preserved.
6. Build clean (`Cmd+Shift+K`) → build (`Cmd+B`) → confirm zero errors. Run on Simulator and confirm the home-screen icon shows **"WatchDog"** (not "BluetoothTesting").

**Acceptance:** A grep for `BluetoothTesting` in the repo returns matches only inside `.xcuserstate` or other generated files (which can be deleted), never in source.

---

## Section 1 — Fix `Info.plist` (currently empty — this is rejection #1)

The current `Info.plist` is `<dict/>` — completely empty. Either populate it directly (legacy approach) **or** drive it from `INFOPLIST_KEY_*` build settings (Xcode 13+ default). Use whichever the existing target is configured for. Do not have both fight each other.

### Required keys (every single one of these must end up in the built `.app/Info.plist`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Identity -->
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>WatchDog</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>WatchDog_iOS</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>1.11.43</string>
    <key>CFBundleVersion</key>
    <string>1</string>

    <!-- Platform -->
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>17.0</string>

    <!-- Launch / scenes -->
    <key>UILaunchScreen</key>
    <dict>
        <key>UIColorName</key>
        <string>AccentColor</string>
    </dict>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>

    <!-- Orientation -->
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
        <string>bluetooth-le</string>
    </array>

    <!-- BLE PRIVACY STRINGS — both keys, even though only one is technically required,
         to cover edge cases where iOS chooses which to display. -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>WatchDog connects to your WatchDog case over Bluetooth to monitor motion, run diagnostics, and update its settings. The app does not use Bluetooth for anything else and never sends Bluetooth data off your device.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>WatchDog connects to your WatchDog case over Bluetooth to monitor motion, run diagnostics, and update its settings.</string>

    <!-- Background modes — ONLY include bluetooth-central if you actually need
         to scan/maintain a connection while backgrounded. If you only do
         disconnect-on-background (which the code currently does), DELETE THIS
         WHOLE BLOCK. Keeping unused background modes triggers Guideline 2.5.4. -->
    <key>UIBackgroundModes</key>
    <array>
        <string>bluetooth-central</string>
    </array>

    <!-- Encryption export compliance — true on-device crypto only (Keychain SecRandomCopyBytes
         is exempt). This declaration lets you skip the U.S. encryption export filing. -->
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
</dict>
</plist>
```

If the target is configured to **generate** `Info.plist` from build settings, replicate every key above as an `INFOPLIST_KEY_*` build setting instead. The two privacy strings (`NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`) **must** be present — the app crashes on first BLE call without them.

### Background mode decision

Look at `BluetoothManager.swift` and `MainAppView.swift` and answer:

> **Does the app need to receive BLE callbacks while backgrounded, or only while foreground?**

`MainAppView.swift` has a 5-second background-disconnect timer (`backgroundDisconnectTimer`) gated on `AppPreferences.disconnectOnBackground`. If that preference defaults to *true* (which the variable name implies), the app does **not** need `bluetooth-central` background mode and you should remove it — it's safer for App Review.

If you keep `bluetooth-central`, you **must**:
- Implement `CBCentralManager` state restoration with `CBCentralManagerOptionRestoreIdentifierKey` and handle the `centralManager(_:willRestoreState:)` delegate callback.
- Be ready to explain to the reviewer (in App Review notes) the user-facing reason — e.g. "the user expects to be notified when their WatchDog case detects motion while the phone is in their pocket."

### Acceptance

- Build settles `Info.plist` into `.app/Info.plist` containing every key above.
- `xcrun plutil -lint <built-app>/Info.plist` passes.
- First launch on a real device prompts for Bluetooth permission with the WatchDog-specific copy from `NSBluetoothAlwaysUsageDescription`.

---

## Section 2 — Add `PrivacyInfo.xcprivacy` (privacy manifest)

As of May 1, 2024, App Store Connect rejects uploads that use **Required Reason APIs** without a privacy manifest. This codebase uses at least:

- `UserDefaults` — required reason API category `NSPrivacyAccessedAPICategoryUserDefaults` (used in `BondManager`, `AppPreferences`, `DeviceNameManager`, `LocalizationManager`, `NavigationStateManager`).

No tracking, no data collection off-device, no third-party SDKs.

### File: `PrivacyInfo.xcprivacy` (place at target root, add to **target membership**)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

Reason `CA92.1` = "Access info from same app, per documentation". This is correct for the way `UserDefaults` is used here (storing the user's bonded-device list, language preference, navigation last-screen, etc.).

### Audit step before committing

Search the codebase for these other Required-Reason APIs and add their reasons if you find them:

| API | Look for | Reason if found |
|---|---|---|
| File timestamp | `creationDate`, `contentModificationDate`, `URLResourceKey.creationDateKey`, `stat`, `fstat`, `getattrlist` | `C617.1` (display to user) |
| System boot time | `systemUptime`, `mach_absolute_time`, `CACurrentMediaTime` | `35F9.1` |
| Disk space | `volumeAvailableCapacityKey`, `NSURLVolumeAvailableCapacityForImportantUsageKey` | `85F4.1` |
| Active keyboards | `UITextInputMode.activeInputModes` | (typically not used) |

Add a `<dict>` entry for each one you actually call.

### Acceptance

- File is in the target's **Compile Sources / Copy Bundle Resources** as appropriate (Xcode auto-detects `.xcprivacy` once added to the target).
- A clean Archive build emits no "Missing privacy manifest" warning.
- Static analysis: `grep -rn "UserDefaults\|systemUptime\|creationDate" --include="*.swift"` matches only declared categories.

---

## Section 3 — Hide debug / developer surfaces from release builds

Reviewers reject apps that expose developer-facing UI under Guideline 2.3.1. The repo contains:

- `Views/Components/DebugGraphs.swift`
- `Models/DiagnosticReport.swift` + `Views/DeviceDiagnosticView.swift`
- `Managers/Log.swift` (verbose logging)
- Top-level prompt files: `FW_DIAG_VERIFICATION_PROMPT.md`, `FW_POWER_OPT_PROMPT.md`, `fix_settings_transition_prompt.md`, `WatchDogBT_Power_Optimization_Research.docx`, the `.usdz` source files

### Required changes

1. **Wrap debug-only views in `#if DEBUG`.**
   - `DebugGraphs` should only be reachable when `#if DEBUG`. If a "Debug" tab/sheet exists in `DevicePageView` or `DeviceDiagnosticView`, gate the *navigation entry point* with `#if DEBUG`, not just the body.
   - The `DeviceDiagnosticView` is probably user-facing (battery diagnostic = legitimate consumer feature). Keep it, but rename any visible string containing "Debug" → "Diagnostics".

2. **Silence release logging.**
   In `Managers/Log.swift`, ensure `os.Logger` calls become no-ops in Release. Pattern:
   ```swift
   #if DEBUG
       logger.debug("\(message)")
   #endif
   ```
   Or gate verbosity by build configuration.

3. **Exclude prompt / research files from the target.**
   Confirm these files are **not** in "Copy Bundle Resources":
   - `FW_DIAG_VERIFICATION_PROMPT.md`
   - `FW_POWER_OPT_PROMPT.md`
   - `fix_settings_transition_prompt.md`
   - `WatchDogBT_Power_Optimization_Research.docx`
   They should not ship inside the `.app`.

4. **`.usdz` files.** `WatchDogBTCase_Final.usdz` and `WatchDogBT_V2.usdz` and `WatchDogBTPCB.usdz` — only the one(s) actually loaded by `SceneView3D.swift` should be in the target's resources. The others (especially `WatchDogBTPCB.usdz` if it's a PCB visualization for engineering, not a consumer-facing view) should be removed from target membership.

### Acceptance

- Open the built `.app` (right-click → Show Package Contents in Finder, or `unzip -l <ipa>`) — confirm only consumer-facing assets are inside.
- A Release build search of the bundle for "Debug" should return no UI strings.

---

## Section 4 — App Icon verification

`Assets.xcassets/AppIcon.appiconset/Contents.json` exists. You must verify:

1. The 1024×1024 marketing icon is present, **PNG, no alpha channel, no transparency, fully opaque background**, and no pre-rendered rounded corners. Apple applies the corner mask itself — supplying a pre-rounded icon causes the corners to be double-masked.
2. Run: `sips -g hasAlpha <path-to-1024.png>` — must report `hasAlpha: no`. If it reports yes, flatten with:
   ```
   sips -s format png --setProperty hasAlpha no <input.png> --out <flattened.png>
   ```
3. All sizes referenced by `Contents.json` exist on disk and are the correct dimensions.
4. The `accent` and `tint` icon variants for iOS 18 dark/tinted home-screen icons are recommended but not required. If you skip them, the system generates them from the standard icon — acceptable for v1.
5. Icon contains no Apple trademark, no map of an Apple device frame, no "beta"/"test" text.

### Acceptance

`xcrun actool --notices --warnings --print-strict-validation-warnings Assets.xcassets ...` passes with no AppIcon warnings.

---

## Section 5 — Privacy Policy

App Store Connect requires a privacy policy URL for every app, even one that collects nothing. Draft the policy (host at e.g. `https://watchdog.app/privacy`) and have the URL ready for the App Store Connect form.

### Required content (covers what this app actually does)

- **What we collect:** Nothing leaves your device. The app stores your bonded WatchDog list, language preference, and a randomly-generated 4-byte loyalty token in your iPhone's local storage (UserDefaults and Keychain). The loyalty token is read by your WatchDog case over Bluetooth so the case knows it's paired with your phone — it is never transmitted anywhere else.
- **Bluetooth:** The app uses Bluetooth solely to communicate with your WatchDog case. Bluetooth scan results are never logged or transmitted off-device.
- **Analytics / tracking:** None. The app contains no analytics SDKs and makes no network requests.
- **Children:** The app is not directed at children under 13 and does not knowingly collect personal information from anyone.
- **Contact:** A real, monitored email address.

Include the URL in: App Store Connect → App Information → Privacy Policy URL, and again in App Privacy → Data Types ("Data Not Collected").

### Acceptance

The Data Types section in App Store Connect can be filled out as **"Data Not Collected"** — verify by re-walking the questionnaire after the privacy manifest is in place.

---

## Section 6 — Hardware accessory App Review survival kit (Guideline 2.1 / 4.2.6)

The app is non-functional without a paired WatchDog. The reviewer cannot pair to your hardware. Without a survival kit, you will be rejected with "we couldn't evaluate the core functionality."

### Required deliverables

1. **App Review notes** in App Store Connect must include:
   - One-paragraph summary of what WatchDog hardware is and what the app does.
   - Statement that the app requires the WatchDog case, **and** instructions for how the reviewer can evaluate it without the hardware (see #2 and #3).
   - A demo video URL (unlisted YouTube/Vimeo, or a direct mp4 hosted somewhere reachable).
   - Optional: offer of a review unit shipped to Apple — `https://developer.apple.com/contact/app-store/review-attachment/`. For BLE accessory apps this dramatically reduces rejection rate.

2. **Demo / showcase mode (recommended).** Add a runtime flag (e.g. `AppPreferences.shared.demoMode` toggled by tapping the version label 7 times, or by a build flag `-DDEMO_MODE`) that:
   - Pre-populates one fake bonded WatchDog so the reviewer can navigate the device page.
   - Drives the 3D model with synthetic motion data.
   - Stubs the BLE diagnostic responses with realistic values.
   This is **the single most effective change** for getting accessory apps approved.

3. **Recorded walkthrough video** (≤ 60 seconds): pairing → device page swipe → 3D model rotation → motion log entry → settings → unpair. Upload, paste URL into App Review notes.

### Acceptance

A QA volunteer who has never seen the app can install it, follow the App Review notes, and reach every primary screen using only the demo mode plus the walkthrough video.

---

## Section 7 — Background BLE: keep it or drop it

Decision tree:

```
Does the app need to react to WatchDog motion events while phone is locked / in pocket?
├── YES → keep `bluetooth-central` in UIBackgroundModes
│         → implement CBCentralManager state restoration:
│             - init with [CBCentralManagerOptionRestoreIdentifierKey: "com.watchdog.central"]
│             - implement centralManager(_:willRestoreState:)
│             - persist active connections so iOS can relaunch and resume
│         → document user benefit clearly in App Review notes
│
└── NO  → REMOVE `bluetooth-central` from UIBackgroundModes entirely
          → keep the existing 5s disconnect-on-background timer
          → simpler review, no Guideline 2.5.4 risk
```

Default recommendation given the current code: **drop `bluetooth-central`**. The disconnect-on-background preference suggests the app is foreground-driven. Reintroduce background BLE in v1.1 once you have user feedback that it's needed.

### Acceptance

If dropping: confirm `UIBackgroundModes` is absent from the built `Info.plist`. App still works correctly when launched, used, backgrounded, and re-foregrounded.

If keeping: confirm `centralManager(_:willRestoreState:)` is implemented and tested by force-quitting via the system (not the debugger) while connected, then re-launching.

---

## Section 8 — Strip developer language from `App/MainAppView.swift` and elsewhere

The file headers contain extensive `── FIX SUMMARY ──` blocks describing internal engineering decisions. These don't ship in the binary so they're not a rejection risk, but you should also audit user-facing strings:

- `LocalizationManager` strings: any key with "test", "debug", "watchdog" lowercased in a way that looks like a placeholder, "TODO", "FIXME", "TBD".
- `TutorialOverlayView`: confirm the tutorial copy is real, polished, and doesn't say "Lorem ipsum" or "test text".
- Error strings: `"WatchDog is not connected."`, `"WatchDog did not confirm unpair within 2 seconds."` — fine, real error messages, but make sure every error path *has* a localized string and isn't falling back to a Swift error description.

### Acceptance

Manual walkthrough of every screen with VoiceOver enabled to surface any text the eye missed.

---

## Section 9 — Localization completeness

`LocalizationManager.swift` exists and is keyed by enum cases. For every language you list in App Store Connect:

1. Confirm a string exists for **every** key the UI calls. A missing key showing the raw enum case name in production = Guideline 2.3.0 rejection.
2. Confirm the `CFBundleLocalizations` build setting / Info.plist key matches the languages you'll list in App Store Connect.
3. Screenshot every screen in every supported language for QA review (you don't submit these screenshots, but you keep them for your records).

If you only want to ship English at v1, **remove** all other languages from `LocalizationManager` and from the App Store Connect language list. Half-translated < monolingual for review purposes.

### Acceptance

`grep -rn '\.t(\.' Views App` shows every key resolved by every language file in `LocalizationManager`. Run a script that diffs key sets across languages — should be empty.

---

## Section 10 — App Store Connect metadata checklist

Have these ready before pressing "Submit for Review":

- [ ] **App Name:** "WatchDog" (12-character version available if needed: "WatchDog")
- [ ] **Subtitle:** ≤ 30 chars, e.g. "Bluetooth case companion"
- [ ] **Promotional text:** ≤ 170 chars (editable post-launch without re-review)
- [ ] **Description:** Lead with what the app does on its own (motion log, diagnostics, 3D viewer), not "you need our hardware". Cite Guideline 4.2.6 directly: "If your app primarily controls hardware, it should also provide value beyond the hardware integration." Mention the on-device data story.
- [ ] **Keywords:** ≤ 100 chars, comma-separated. e.g. `watchdog,case,bluetooth,ble,motion,tracker,companion,smart case`
- [ ] **Support URL:** A real, reachable webpage with a contact form or email.
- [ ] **Marketing URL:** Optional but recommended — product landing page.
- [ ] **Privacy Policy URL:** Required. Must load over HTTPS and not 404.
- [ ] **Category — Primary:** Utilities (or Lifestyle if motion-tracking framing is stronger). **Secondary:** optional.
- [ ] **Age Rating:** complete the questionnaire. Expected outcome: **4+**.
- [ ] **Screenshots:**
  - 6.9" iPhone 17 Pro Max (1320 × 2868)
  - 6.7" iPhone 15 Plus (1290 × 2796)
  - 6.5" iPhone 11 Pro Max (1284 × 2778) — optional now but improves coverage
  - iPad 13" if iPad supported
  - Minimum 3 screenshots per size, maximum 10.
  - **No** debug graphs visible. **No** developer placeholder text. Real-looking data.
- [ ] **App Preview video** (optional, 15–30s, can really help accessory apps)
- [ ] **App Review notes:** demo-mode instructions + walkthrough video URL + offer of review unit.
- [ ] **Build:** uploaded via Xcode Archive, processed, attached to this version.
- [ ] **Encryption documentation:** none required because `ITSAppUsesNonExemptEncryption = false` in Info.plist (set in Section 1).
- [ ] **Content rights:** confirm you have rights to all assets (USDZ models, icon, etc.).

---

## Section 11 — Final pre-flight build

After every section above is done, run this checklist:

1. `xcodebuild clean -scheme WatchDog_iOS`
2. `xcodebuild archive -scheme WatchDog_iOS -archivePath build/WatchDog_iOS.xcarchive -destination 'generic/platform=iOS'`
3. Inspect the archive: `plutil -p build/WatchDog_iOS.xcarchive/Products/Applications/WatchDog_iOS.app/Info.plist`
   - `CFBundleDisplayName` == `WatchDog` ✓
   - `NSBluetoothAlwaysUsageDescription` present ✓
   - `ITSAppUsesNonExemptEncryption` == false ✓
4. `find build/WatchDog_iOS.xcarchive -name "PrivacyInfo.xcprivacy"` returns one path inside the `.app` ✓
5. Validate archive in Organizer → "Validate App". Resolve every warning.
6. Test install on a real device via TestFlight or `Distribute App → Development`. First launch:
   - Bluetooth permission prompt shows the WatchDog-specific copy.
   - App does not crash on permission denial.
   - App icon shows "WatchDog" on home screen.
7. Run with WatchDog hardware (if available) end-to-end: pair, browse, diagnose, unpair, re-pair, background, return.
8. Run **without** WatchDog hardware: enable demo mode and walk every screen.
9. Run with airplane mode on, then off — confirm BLE state transitions cleanly.
10. Run with Bluetooth permission **denied** — confirm a graceful "Bluetooth permission required" UI, not a crash.

---

## Section 12 — What to deliver back to me

When done, produce:

1. A short **CHANGES.md** at the repo root summarizing every file added/modified per section above.
2. The new `Info.plist` (or the equivalent `INFOPLIST_KEY_*` build settings, listed).
3. The new `PrivacyInfo.xcprivacy`.
4. A note on the background BLE decision (kept vs dropped) with one-sentence rationale.
5. Confirmation that a Release Archive build succeeds with zero warnings related to these changes.
6. A list of any items you couldn't complete autonomously (e.g. "needs final bundle ID from product owner", "needs hosted privacy policy URL") with clear placeholders in the codebase.

---

## Section 13 — Out of scope (do not do)

- Do **not** add Sign in with Apple, accounts, or any auth.
- Do **not** add analytics, crash reporting, or any third-party SDK.
- Do **not** add ATT (App Tracking Transparency) — there is no tracking.
- Do **not** add IAP / subscriptions.
- Do **not** add network calls of any kind.
- Do **not** rewrite `BluetoothManager` — it has invariants documented in its header comment that should be respected.
- Do **not** change the data model (`BondedDevice`, `BluetoothDevice`, `MotionEvent`, etc.) beyond what's needed for the rename.

---

## Quick-reference summary of every fix

| # | Fix | Impact |
|---|---|---|
| 0 | Rename project → `WatchDog_iOS`, display name → "WatchDog" | Unblocks 2.3.0 / 4.0 |
| 1 | Populate `Info.plist` (Bluetooth strings, all standard keys, encryption flag) | Unblocks 2.1 / 5.1.1 / crash on first BLE call |
| 2 | Add `PrivacyInfo.xcprivacy` declaring UserDefaults reason | Unblocks ASC upload validator |
| 3 | Hide debug surfaces (`DebugGraphs`, prompt files, verbose logs) | Unblocks 2.3.1 |
| 4 | Verify 1024×1024 icon is opaque PNG | Unblocks mechanical rejection |
| 5 | Write & host privacy policy | Required by ASC |
| 6 | Demo mode + walkthrough video + App Review notes | Unblocks 2.1 / 4.2.6 (accessory apps) |
| 7 | Background BLE: drop unless needed; otherwise add state restoration | Unblocks 2.5.4 |
| 8 | Audit user-facing strings for placeholders/dev language | Polish |
| 9 | Localization completeness | Unblocks 2.3.0 |
| 10 | App Store Connect metadata (screenshots, description, etc.) | Required to submit |
| 11 | Final pre-flight archive + validate + device test | Confidence |
| 12 | Deliverables back to product owner | Handoff |

End of prompt.
