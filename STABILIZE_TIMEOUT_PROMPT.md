# iOS: "Hold to Stop" while stabilizing + 15 s timeout coordination

## Two coordinated changes

1. **iOS-only:** the lock button currently shows the hardcoded text "Stabilizing..." while the firmware is in `STATE_STABILIZING`. Change it to a localized "Hold to Stop", and let the existing hold gesture finish a hold (which already un-arms the device — that path is correct, just unlabelled today).
2. **Firmware-side, no iOS code work needed:** the firmware Claude Code instance is adding a 15 s timeout to `STATE_STABILIZING` (prompt at `TheWatchDogBT/STABILIZE_TIMEOUT_PROMPT.md`). When the timeout fires, the firmware transitions to `STATE_CONNECTED_IDLE` and pushes a status notification with `ARMED=0`. iOS's existing `syncLockedFromDeviceIfApplicable` reactively flips `isLocked` to `false`, so the UI handles this automatically.

## Where the iOS change goes

`WatchDog_iOS/Views/Components/LockButton.swift` (the whole file is small — ~80 lines).

Currently:

```swift
private var buttonText: String {
    let loc = LocalizationManager.shared
    if isStabilizing { return "Stabilizing..." }
    return isLocked ? loc.t(.holdToUnlock) : loc.t(.holdToLock)
}
```

After:

```swift
private var buttonText: String {
    let loc = LocalizationManager.shared
    if isStabilizing { return loc.t(.holdToStop) }
    return isLocked ? loc.t(.holdToUnlock) : loc.t(.holdToLock)
}
```

Also remove the `&& !isStabilizing` clause from the progress overlay so the user can see the hold-fill bar progress while stabilizing — without it, holding to stop gives no feedback that the hold is registering:

```swift
// Before
if !isDisabled && !isStabilizing {
    GeometryReader { geometry in ... }
}
// After
if !isDisabled {
    GeometryReader { geometry in ... }
}
```

The `phaseAnimator` blue pulse can stay — the white progress overlay reads cleanly on top of the pulsing background.

The icon (`lock.rotation` while stabilizing) is fine to leave alone, but if you'd rather signal "stop" more clearly, `xmark.octagon.fill` or `stop.fill` are reasonable alternatives. Up to you — flag it in your commit message either way.

## New localization key

`WatchDog_iOS/Managers/LocalizationManager.swift`:

1. Add `holdToStop` to the `LocKey` enum (around line 47, next to `holdToLock`/`holdToUnlock`):

   ```swift
   case holdToLock, holdToUnlock, holdToStop
   ```

2. Add a translation in **every** language table (English, Spanish, Dutch, French, Japanese, Portuguese — the same six the existing `holdToLock`/`holdToUnlock` keys cover). Suggested strings, but feel free to refine:

   | Language   | String                       |
   |------------|------------------------------|
   | English    | `Hold to Stop`               |
   | Spanish    | `Mantén para Detener`        |
   | Dutch      | `Houd vast om te Stoppen`    |
   | French     | `Maintenir pour Arrêter`     |
   | Japanese   | `長押しで停止`                  |
   | Portuguese | `Manter para Parar`          |

   Match the casing/style of the surrounding `holdToLock`/`holdToUnlock` entries in each table. If any language has the entries on a single concatenated line (e.g. English line 120-121), keep that style.

## Why the hold gesture already does the right thing

`DevicePageView.swift::completeHold()` (~line 762):

```swift
let newArmed = !isLocked
settingsManager.updateSettings(armed: newArmed)
settingsManager.setPersistedArmed(newArmed, for: deviceID)
bluetoothManager.sendSettings()
...
isLocked = newArmed
```

While stabilizing, `isLocked == true` (the user just hit Hold to Lock — the firmware is settling toward `STATE_LOCKED`, but iOS already flipped `isLocked` on the lock-side hold). A completed hold therefore sends `armed=false`, which the firmware receives and uses to drop out of `STATE_STABILIZING` back to `STATE_CONNECTED_IDLE`. No new gesture handling needed.

The hold duration in `startHolding` is `isLocked ? 0.6 : 0.91` — during stabilizing `isLocked` is true, so a 0.6 s hold to stop. That matches "hold to unlock" behaviour, which is the right intuition.

## Verification (after firmware build with 15 s timeout is on a unit)

- **Hold to Stop during stabilize.** Hold to Lock → blue pulse starts → during the pulse, hold the button. Expect: white fill bar progresses over 0.6 s, the device un-arms, status text returns to "Unlocked".
- **15 s firmware timeout.** Hold to Lock under continuous motion (shake the device) so it can't settle. Expect: at ~15 s the button reverts to "Hold to Lock" and the device unlocks on its own (firmware-driven via status notification — no iOS work).
- **Normal lock.** Hold to Lock → place device still → firmware locks within 3 s. Button transitions through "Hold to Stop" briefly during the blue pulse, then to "Hold to Unlock" once locked.
- **All six locales.** Switch the app language and confirm the translated "Hold to Stop" string appears.

## Don't touch

- `startHolding` / `stopHolding` / `completeHold` logic — already correct.
- `mlcState` / `deviceState` parsing in `BluetoothManager`.
- The `.locking` localized status text used by `statusText` in `DevicePageView` — that's the small label above the button, separate from the button itself, and still says "Locking" (or its localized variant) while stabilizing. Different concept.

## Version bump

Per `CLAUDE.md`, follow the version recompute. Comment+behaviour change so a real bump is appropriate. If committing on `dev`: +1 to `AppVersion.v2`. If on `main`: +1 to `MAIN`, reset `V2` to `0`. Update `AppVersion.swift` and the `Current: V…` + reconciled-sha line in `CLAUDE.md` in the same commit. Commit message: `version bump to Vx.y.z`.
