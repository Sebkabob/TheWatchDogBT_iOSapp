# APP_RAW_STREAM_PROMPT — raw accel capture & 50/100 Hz comparison

## Why this exists

We want training data for a new LIS2DUX12 FSM that detects door
openings. The firmware change in `FW_RAW_STREAM_PROMPT.md` (over in
the `TheWatchDogBT` repo) adds a debug-only raw streaming mode that
pushes 100 Hz accel samples over BLE. The iOS app needs a debug-menu
hook to capture that stream, optionally decimate it to 50 Hz, and
export a CSV that drops cleanly into ST's MEMS Studio Unico-GUI for
FSM training.

We're trying to answer one question with this UI: **does 50 Hz
training data classify door openings as well as 100 Hz, or do we need
the higher rate?** Same hardware feed for both, decimated app-side, so
A/B comparisons are honest.

## What the user sees

In the existing **Debug** menu (wherever the diagnostic / dev tools
live — drain mode, find-my, etc. should be neighbours), add a new
section: **"Raw accel capture"**.

Layout:

```
Raw accel capture
─────────────────────────────────
  Output rate     [ 50 Hz | 100 Hz ]   ← segmented control, default 100
  ─────────────────────────────────
  ▶ Start capture                       ← tappable; switches to ⏹ Stop
  ─────────────────────────────────
  Samples         12,403
  Duration        00:02:04
  Drops (firmware) 7  (0.06 %)
  Last sample     X: -32  Y:  18  Z: 1003 mg
  ─────────────────────────────────
  Export latest CSV   ⓘ                 ← share-sheet, only enabled
                                          when a capture exists
```

Behaviour:

- **Output rate**: pure app-side decimation choice. Has no effect on
  the firmware. 50 Hz drops every other received sample; 100 Hz keeps
  every sample. Tappable any time, including mid-capture.
- **Start/Stop**: sends the firmware opcode (see "BLE protocol"
  below). Capture lives in memory; user must export to keep it.
- **Samples / Duration**: counters update live. Counter shows
  *post-decimation* count (i.e. what will end up in the CSV at the
  current rate setting), not raw received count.
- **Drops (firmware)**: derived from `seq` gaps in the stream — see
  "drop counting" below. Useful to spot a flaky link before wasting a
  capture.
- **Last sample**: small live preview. Updates at most ~10 Hz so the
  label doesn't thrash.
- **Export latest CSV**: shares to Files / Mail / AirDrop. Format
  below.

The control should remain visible even when no device is connected;
disable Start with a hint ("Connect to a WatchDog first") so the
debug surface is discoverable without a device.

## BLE protocol (mirrors `FW_RAW_STREAM_PROMPT.md`)

### Command (write to `APPTOWD`)

`CMD_RAW_STREAM = 0xF5`

Wire format: `[loyalty(4)] [0xF5] [flags(1)]`

`flags & 0x01`: 1 = start, 0 = stop. Other bits reserved.

### Notification (subscribe to `RAWACCEL`)

New characteristic on the existing `LockService` (`0x183E`). 16-bit
UUID; the firmware change picks the next free value after
`BATTERYDIAG` — discover by UUID at connect, don't hard-code the
handle.

20-byte fixed payload, little-endian throughout:

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0..1   | u16  | `seq`   | Resets to 0 on each stream start. Wraps. |
| 2..3   | u16  | `t_ms`  | Low 16 bits of firmware HAL_GetTick(). |
| 4..5   | i16  | `x_mg`  | |
| 6..7   | i16  | `y_mg`  | |
| 8..9   | i16  | `z_mg`  | |
| 10..19 | —    | reserved | Zero-fill today, may carry temp/flags later. |

Single sample per packet. `seq` is canonical for drop detection;
`t_ms` is for jitter sanity-check only, not for resampling.

## App architecture

### Connection layer

- Existing BLE manager (the one that handles `DEVICESTATUS`,
  `BATTERYDIAG`, etc.) gains a `RawAccelStream` peer object.
- On connect: discover the new characteristic by UUID, cache the
  reference. Do NOT auto-subscribe — only subscribe when the user
  taps Start, and unsubscribe on Stop.
- On disconnect: `RawStreamSession` is finalised (or discarded if
  empty); UI returns to idle.

### Capture session model

```swift
final class RawStreamSession {
    let id: UUID                    // ties to filename
    let startedAt: Date
    private(set) var endedAt: Date?
    private(set) var samples: [DecimatedSample] = []
    private(set) var rawSampleCount: Int = 0
    private(set) var firmwareDrops: Int = 0
    private(set) var lastSeq: UInt16? = nil
    var outputRate: OutputRate      // .hz50 / .hz100; mutable mid-session
}

struct DecimatedSample {
    let seq: UInt16                 // firmware seq (post-decimation: even-only at 50 Hz)
    let tMs: UInt16
    let xMg: Int16
    let yMg: Int16
    let zMg: Int16
    let receivedAt: Date            // host clock at packet receive
}

enum OutputRate { case hz50, hz100 }
```

### Per-packet handling

```
on RAWACCEL notification (data: 20 bytes):
    seq   = read_u16_le(data, 0)
    t_ms  = read_u16_le(data, 2)
    x_mg  = read_i16_le(data, 4)
    y_mg  = read_i16_le(data, 6)
    z_mg  = read_i16_le(data, 8)

    session.rawSampleCount += 1

    if let last = session.lastSeq {
        let expected = last &+ 1
        if seq != expected {
            // gap — count missing samples between expected..<seq
            let gap = Int(seq &- expected) & 0xFFFF
            session.firmwareDrops += gap
        }
    }
    session.lastSeq = seq

    keep = (session.outputRate == .hz100) || (seq % 2 == 0)
    if keep {
        session.samples.append(DecimatedSample(seq, t_ms, x_mg, y_mg, z_mg, Date()))
    }

    throttle UI label updates to ~10 Hz
```

Notes:

- The `&+` / `&-` are unsigned wrap-aware. `seq` is u16, so a 60 s
  capture at 100 Hz wraps after ~10 minutes — handle the wrap
  explicitly (the `&-` modular subtraction does it correctly for any
  gap < 32768).
- 50 Hz uses **even seqs only** (`seq % 2 == 0`). Pinning the parity
  makes captures reproducible and gives the FSM trainer a uniform
  cadence even across small drops. If a packet with `seq=4` is
  dropped, `seq=6` is still kept — the cadence stays at 20 ms.
- Toggling rate mid-capture flips the keep-rule for subsequent
  packets only. Already-stored samples are not retroactively
  filtered. UI should show a small "rate changed at sample #N"
  marker if this matters; otherwise just live with it.

### Memory budget

100 Hz × 60 s × ~24 bytes/sample = ~144 KB per minute. Bound the
in-memory buffer at, say, 30 minutes (~4 MB); auto-stop with a toast
beyond that. We are not building a long-recording system.

### CSV format (Unico-compatible)

Filename: `watchdog_raw_<deviceId>_<startISO8601>_<rate>Hz.csv`

Header row + samples:

```
A_x [mg],A_y [mg],A_z [mg]
-32,18,1003
-31,19,1004
...
```

Three columns, no timestamp column, no header metadata block — this is
exactly what Unico-GUI's "Load from file" expects for FSM training.
Add a *companion* `.meta.json` next to the CSV with everything else
(deviceId, fw version from `DEVICESTATUS` byte 16..18, app version,
start/end timestamps, raw vs kept counts, firmware drops, output
rate, output rate changes if any). The meta file isn't fed to Unico
— it's just so Sebastian can audit a capture six months from now.

Example meta:

```json
{
  "deviceShortId": "A4F3",
  "firmwareVersion": "1.13.0",
  "appVersion": "1.11.54",
  "startedAt": "2026-05-08T14:22:11Z",
  "endedAt":   "2026-05-08T14:24:15Z",
  "outputRate": "100Hz",
  "rawSamples": 12410,
  "keptSamples": 12403,
  "firmwareDrops": 7,
  "notes": ""
}
```

Provide a small text field (optional) below "Export latest CSV"
labelled "Notes" that gets written into `notes` — invaluable for
labelling a clip "front door, slow open" while the user remembers.

### Capture browser (nice-to-have, not blocking)

A second screen that lists past in-memory captures with size /
duration / rate / notes and per-row Export. Scope this only if the
in-memory architecture above is already done — don't persist captures
to disk in the v1.

## Edge cases / gotchas

- **Subscribing fails or characteristic missing**: device firmware is
  too old. Show "Raw streaming requires firmware ≥ Vx.y.z" in the
  card and disable Start. Read fw version from `DEVICESTATUS` byte
  16..18 (already exposed) to gate this.
- **Disconnect mid-capture**: stop and finalise the session so the
  user can still export what was captured. Show a transient banner
  ("Capture ended — disconnect").
- **Mid-capture rate toggle**: legal, see above. Tag the change in
  meta.
- **Stop while another debug feature is active** (drain mode, find-my,
  etc.): independent feature on the firmware side; no UI coupling
  required, but consider greying Start while drain is on so the user
  doesn't get a 100 Hz stream contaminated by a 60 Hz buzzer-induced
  vibration. Cosmetic, not correctness.
- **Background**: iOS BLE notifications continue in background only
  briefly. Do not promise reliable long captures with the screen off.
  This is a foreground debug tool.

## Testing checklist

- [ ] Capture at rest, 100 Hz, 60 s: ~6,000 samples, ≤ 60 firmware
      drops, |z| ≈ 1000 mg, std-dev < 30 mg per axis.
- [ ] Capture at rest, 50 Hz, 60 s: ~3,000 kept, even-seq parity,
      `(rawSamples - firmwareDrops) ≈ 2 × keptSamples`.
- [ ] Tap during capture: visible impulse at the expected sample
      cadence in the resulting CSV.
- [ ] Toggle 100→50 mid-capture: subsequent samples decimated; meta
      records the change.
- [ ] Disconnect mid-capture: session finalises, Export still works,
      meta `endedAt` is set, `notes` is whatever was typed.
- [ ] Older firmware without `RAWACCEL`: feature gracefully disabled.
- [ ] CSV opens in MEMS Studio Unico-GUI without column-mapping
      errors.

## File-touch list (illustrative — match the existing app structure)

- `WatchDog_iOS/Sources/.../Debug/RawAccelCaptureView.swift` (new)
- `WatchDog_iOS/Sources/.../Debug/RawStreamSession.swift` (new)
- `WatchDog_iOS/Sources/.../BLE/RawAccelService.swift` (new — UUID,
  subscribe/unsubscribe helpers)
- `WatchDog_iOS/Sources/.../BLE/BLEManager.swift` (edited — wire up
  the new characteristic & start/stop opcode)
- `WatchDog_iOS/Sources/.../Debug/DebugMenuView.swift` (edited — add
  the new card / row)
- `WatchDog_iOS/Sources/.../Export/RawStreamCSVExporter.swift` (new)
- `AppVersion.swift` + reconciled-sha — version bump on commit per
  `CLAUDE.md` rules.
