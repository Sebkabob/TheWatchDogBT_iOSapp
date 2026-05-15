# iOS: motion-log timestamps (send the calendar anchor, stop faking it)

## The bug

Every entry in the motion log view shows up with the current wall-clock time of the iPhone — not the time the event actually happened. Two iOS bugs combine to produce this:

1. **`sendSettings()` never appends the 6-byte timestamp tail the firmware is waiting on.** The firmware contract (in `lockservice_app.c`) is: any non-opcode settings write of length ≥ 7 bytes (after token strip) carries `[YY-2000, MM, DD, hh, mm, ss]` in the trailing 6 bytes, which the firmware feeds to `MotionLogger_SetBootTime()` to anchor its internal `HAL_GetTick()` counter against calendar time. Today `sendSettings()` writes 4 bytes, the firmware's `cmd_length >= 7` gate fails, and the firmware's `boot_time.valid` is **permanently 0**. Confirmed by grepping the whole iOS workspace — there is no other call site that constructs the tail.
2. **The `RESP_EVENT_DATA` parser silently substitutes `Date()` when the firmware reports an unknown time.** With `boot_time.valid == 0`, the firmware's `MotionLogger_TickToDateTime()` falls back to `(year=0, month=1, day=1, 00:00:00)` for every event. The iOS handler in `BluetoothManager.swift:1089–1101` interprets that sentinel as "use the current iPhone time," which is exactly the symptom on screen.

Fix iOS on both fronts. The firmware side has a small companion fix described in `TheWatchDogBT/MOTION_LOG_TIMESTAMP_FIX_PROMPT.md` to harden the wire contract — read that too, but iOS is the originating bug and can ship independently.

## Where the iOS changes go

`WatchDog_iOS/Managers/BluetoothManager.swift`
`WatchDog_iOS/Models/MotionEvent.swift`
`WatchDog_iOS/Views/MotionLogsView.swift` (display side)

## Change 1 — `sendSettings()` must append the 6-byte calendar tail

`BluetoothManager.swift:675–684`. Current code:

```swift
func sendSettings() {
    guard !isDemoMode else { return }
    let settingsByte = settingsManager.encodeSettings()
    let deviceInfoByte = settingsManager.encodeDeviceInfo()
    let alarmDurationByte = settingsManager.encodeAlarmDuration()
    let ledBrightnessByte = settingsManager.encodeLEDBrightness()
    let data = Data([settingsByte, deviceInfoByte, alarmDurationByte, ledBrightnessByte])
    sendData(data)
    Log.tx(.settings, "Sent settings · ...")
}
```

After (append 6 bytes of `now`, in local time):

```swift
func sendSettings() {
    guard !isDemoMode else { return }
    let settingsByte      = settingsManager.encodeSettings()
    let deviceInfoByte    = settingsManager.encodeDeviceInfo()
    let alarmDurationByte = settingsManager.encodeAlarmDuration()
    let ledBrightnessByte = settingsManager.encodeLEDBrightness()

    var data = Data([settingsByte, deviceInfoByte, alarmDurationByte, ledBrightnessByte])
    data.append(contentsOf: Self.currentLocalCalendarBytes())
    sendData(data)
    Log.tx(.settings, "Sent settings + anchor · 0x\(String(format: "%02X", settingsByte)) ...")
}

/// `[YY-2000, MM, DD, hh, mm, ss]` in the device user's local time.
/// Local — not UTC — because the firmware just adds elapsed ticks and reports
/// the result back verbatim; iOS doesn't apply a timezone on the way back in
/// (`RESP_EVENT_DATA` parser builds the Date with `Calendar.current`, which
/// is local). Keep both ends in local time so they round-trip cleanly.
private static func currentLocalCalendarBytes() -> [UInt8] {
    let now = Date()
    let cal = Calendar.current
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
    let yy = UInt8(max(0, min(255, (c.year ?? 2000) - 2000)))
    return [
        yy,
        UInt8(c.month  ?? 1),
        UInt8(c.day    ?? 1),
        UInt8(c.hour   ?? 0),
        UInt8(c.minute ?? 0),
        UInt8(c.second ?? 0),
    ]
}
```

Why this works on the firmware side: `lockservice_app.c:385–390` already does

```c
if (cmd_length >= 7 && command != CMD_REQUEST_EVENT && ...) {
    UpdateBootTimeFromiOS(&cmd_data[cmd_length - 6]);
}
```

Once `cmd_length == 10` (4 settings bytes + 6 calendar bytes after token strip), the gate trips and `MotionLogger_SetBootTime()` runs. No firmware change is *required* to start fixing the symptom — the contract has been in place all along, iOS just never honored it.

### Call `sendSettings()` proactively at the right moments

`sendSettings()` is already called on every settings change (lock toggle, sensitivity change, etc.) and on the explicit connect handshake. Confirm it also runs **right after loyalty verification completes** so the anchor is set before the user can request the log. Audit the connect path (`centralManager(_:didConnect:)`, `centralManagerDidUpdateState`, and `BluetoothManager.swift` near line 1311) and make sure one `sendSettings()` fires unconditionally after `loyaltyState == .verified`. If the current connect flow already does this implicitly via a settings broadcast, fine — but verify it; don't assume.

Optionally, re-send a fresh anchor right before the first `requestMotionLogCount()`. The firmware's `TickToDateTime` recomputes calendar time from `(boot_time + elapsed_ms_since_anchor)`, so the more recently the anchor was set, the smaller the accumulated drift from any quartz inaccuracy. Cheap insurance; one extra 10-byte write per log-view session.

## Change 2 — stop pretending unknown times are "now"

`BluetoothManager.swift:1080–1123`. Current behavior at lines 1089–1101 collapses the firmware's "I don't know" sentinel into `Date()`:

```swift
var timestamp: Date
if year == 0 && month <= 1 && day <= 1 {
    timestamp = Date()                          // ← lies
} else {
    var components = DateComponents()
    components.year   = 2000 + Int(year)
    components.month  = max(1, Int(month))
    components.day    = max(1, Int(day))
    components.hour   = Int(hour)
    components.minute = Int(minute)
    components.second = Int(second)
    timestamp = Calendar.current.date(from: components) ?? Date()
}
```

Replace with an optional that the UI can render distinctly:

```swift
let timestamp: Date? = {
    // Firmware's "unanchored" sentinel: year=0, month=1, day=1, time=00:00:00.
    // Treat as missing rather than fabricating a wall-clock time.
    if year == 0 && month == 1 && day == 1 && hour == 0 && minute == 0 && second == 0 {
        return nil
    }
    var components = DateComponents()
    components.year   = 2000 + Int(year)
    components.month  = max(1, Int(month))
    components.day    = max(1, Int(day))
    components.hour   = Int(hour)
    components.minute = Int(minute)
    components.second = Int(second)
    return Calendar.current.date(from: components)
}()
```

…and propagate the optional into `MotionEvent`.

## Change 3 — `MotionEvent.timestamp` becomes optional

`WatchDog_iOS/Models/MotionEvent.swift`:

```swift
struct MotionEvent: Identifiable, Codable {
    let id: UUID
    let deviceID: UUID
    let timestamp: Date?                         // ← was: Date
    let eventType: MotionEventType
    let alarmSounded: Bool

    init(id: UUID = UUID(), deviceID: UUID, timestamp: Date?, eventType: MotionEventType, alarmSounded: Bool) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.eventType = eventType
        self.alarmSounded = alarmSounded
    }
}
```

This will cascade through call sites — fix each compile error explicitly; don't paper over with force-unwraps. Likely touch points:
- `MotionLogManager.swift` — date-based grouping / sorting. Events with `timestamp == nil` should sort to a dedicated "Unknown time" group (top or bottom — your call, but be deliberate; I'd suggest top so the user notices). Sorting comparators on `Optional<Date>` need a tiebreaker (`id` works) to keep the order stable.
- `MotionLogsView.swift:199, 212` — `calendar.startOfDay(for: event.timestamp)` and `dateComponents(...from: event.timestamp)`. Both need `if let` guards.
- `MotionLogsView.swift:382, 561` — display formatters. Render `timestamp == nil` as `"—"` or a localized "Unknown time" string. The row in `MotionEventRow` (~line 557) is the most user-visible spot.

Add a localization key for the unknown-time string in `LocalizationManager.swift` and translate it across all six locales (English, Spanish, Dutch, French, Japanese, Portuguese), matching the casing/style of nearby entries. Suggested strings:

| Language   | String          |
|------------|-----------------|
| English    | `Unknown time`  |
| Spanish    | `Hora desconocida` |
| Dutch      | `Tijd onbekend` |
| French     | `Heure inconnue` |
| Japanese   | `時刻不明` |
| Portuguese | `Hora desconhecida` |

## Change 4 — clear-after-download is the right default; keep it

`BluetoothManager.swift:1120` already calls `self.clearMotionLog()` after the last event is pulled. Keep that. It bounds how stale a `nil` timestamp can ever be: at most one motion event that happened between the previous log-view session and the next reboot/anchor. Without this, the unknown-time bucket would grow unboundedly across firmware reboots that happen before iOS reconnects.

## Verification

Run these on a real device with a freshly flashed firmware build that has the companion fix applied (or even with current firmware — Change 1 alone should already produce correct timestamps for current-session events). Each test should be a fresh BLE connect.

1. **Happy path, current session.** Connect → arm → leave on a table → walk over and shake it → unarm → open Motion Logs. Expect: event time is "a few seconds ago," not "now." Time of day matches the phone clock within 1–2 s.
2. **Multiple events with realistic gaps.** Trigger four events spaced ~10 s apart. Expect: four rows with monotonically increasing timestamps, each ~10 s after the previous one. Not all stamped with the same `Date()`.
3. **Event before iOS connects.** Arm device, disconnect iOS, wait 60 s, trigger motion, reconnect iOS, open logs. Expect: with firmware companion fix applied, event shows up ~60 s before the connect moment. Without the companion fix, expect it to show ~at-connect time (a known firmware limitation — see firmware prompt) but **never** stamped as the moment of log-view open.
4. **Cold reboot mid-session.** Arm, trigger one motion, force a firmware reboot (cable cycle), reconnect, open logs. Expect: the event survives EEPROM-side, but its timestamp may be wrong until the firmware-side persistence work (also covered in the firmware prompt) lands. For this PR, just confirm it's labeled "Unknown time" rather than "now."
5. **Date rollover.** Set the phone to ~23:59, arm, wait past midnight, trigger an event, view logs. Expect: event row shows yesterday's date and ~23:59, not today.
6. **Timezone change.** Arm, trigger an event, change the phone timezone forward 5 hours, view logs. Acceptable result: event time shifts with the timezone (since we encoded local time). Note this in the commit message — full TZ correctness is out of scope.
7. **All six locales.** Switch the app language. Confirm "Unknown time" is localized in any row that surfaces it (force one by clearing the firmware's anchor — e.g., reboot the device and view logs before sending settings).
8. **Don't anchor the firmware in demo mode.** `sendSettings()` already early-returns in demo mode; confirm the new code path also respects the `isDemoMode` guard (it's the first line).

## Don't touch

- The firmware-side fallback `(0,1,1,0,0,0)` is the canonical "unknown" sentinel. Don't try to detect "unknown" by other means (e.g., `year < 25`) — that will misfire on real events.
- The `clearMotionLog()` call after the last download — see Change 4.
- The 4-byte loyalty token prefix in `sendData()`. The new timestamp tail goes *after* the settings payload, inside the iOS-side payload that `sendData()` then prefixes the token onto.
- Other writes (`sendPing`, `sendResetDevice`, `requestDiagnosticDump`, log-related opcodes) — these are opcode commands, not settings writes, and the firmware explicitly excludes them from the boot-time tail check.

## Version bump

Per `CLAUDE.md`, run the version recompute first thing. This is a behaviour change so bump regardless of touch count. If committing on `dev`: +1 to `AppVersion.v2`. If on `main`: +1 to `MAIN`, reset `V2` to `0`. Update `AppVersion.swift` and the `Current: V…` + reconciled-sha line in `CLAUDE.md` in the same commit. Commit message: `version bump to Vx.y.z`.
