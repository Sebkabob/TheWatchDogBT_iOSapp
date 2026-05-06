# WatchDogBT — Firmware data-definition verification request

The iOS app now decodes the on-demand TLV diagnostic blob delivered on the
`BATTERYDIAG` characteristic in response to `CMD_REQUEST_DIAG` (0xF4). Two
fields are suspected to have **incorrect interpretations on the iOS side** —
specifically `OpConfig` SLEEP-bit position and `chem_id_read`'s expected
value. Rather than guess, we want firmware to reconfirm **every** field of
the v1 TLV format byte-for-byte. Wherever the iOS app's current
interpretation is wrong, please flag the correct one.

This is purely a documentation / spec-confirmation pass — no firmware code
changes are being requested. The goal is a single authoritative reply that
either says "all of the below are correct" or, for each item, gives the
right value, range, expected-good case, and bit interpretation.

For each section below, please reply inline (or in a clearly-labelled
follow-up) with one of:

- **OK** — the iOS interpretation matches the firmware truth.
- **WRONG: …** — describe the correct layout / value / bit position. If
  the field's *meaning* changed in a recent firmware revision, note that
  too so we can version-gate.

---

## Header (every TLV reply)

```
byte 0 : format_version  (currently 1; bump = breaking change to header)
byte 1 : section_count   (count of sections that follow)
```

Per-section framing:

```
byte 0 : section_id      (1..0xFE; 0xFF reserved as future end-marker)
byte 1 : section_len     (N — payload bytes that follow)
bytes 2..N+1 : payload   (layout per section_id below)
```

All multi-byte integers little-endian. iOS reads exactly `section_len` bytes
per section and ignores trailing bytes. Confirm.

---

## `0x01` SYSTEM (currently 19 bytes)

| Off | Type   | Field             | iOS-side interpretation |
|-----|--------|-------------------|--------------------------|
| 0   | u32 LE | `uptime_seconds`  | seconds since most recent boot |
| 4   | u32 LE | `boot_count`      | EEPROM-persisted, +1 per boot |
| 8   | u8     | `reset_cause`     | latched RCC->CSR flags packed: bit0 PAD, bit1 POR/BOR, bit2 SFT, bit3 WDG, bit4 LOCKUP. iOS treats WDG and LOCKUP as red flags. |
| 9   | u8     | `fw_version_major`| matches DEVICESTATUS bytes 16..18 |
| 10  | u8     | `fw_version_main` | |
| 11  | u8     | `fw_version_v2`   | |
| 12  | u8     | `init_bitmask`    | bit0 I2C, bit1 BQ27427, bit2 LIS2DUX12, bit3 EEPROM, bit4 Loyalty, bit5 MotionLogger, bit6 BLE. iOS expects **0x7F** (all 7 bits set) as healthy. Bit 7 is currently treated as reserved/unused — confirm? |
| 13  | u8     | `last_fault_marker` | 0 = clean; non-zero = previous boot ended in HardFault. iOS expects 0 in the field; firmware will populate later. |
| 14..18 | u8 × 6 | reserved      | all zero in v1 (note: iOS doesn't assume length of trailing reserved bytes) |

**Questions:**

1. Is `init_bitmask` bit 7 actually used today? (App is alarming on anything
   < 0x7F. If a 7th subsystem exists we'll miss it; if bit 7 is reserved
   for future, confirm 0x7F = healthy.)
2. Are reset-cause bit positions truly 0..4, or have they shifted to align
   with vendor `RCC_FLAG_*` macros?

---

## `0x02` BATTERY (currently 51 bytes — v11 packet)

iOS reuses its existing `BatteryDiagnostic` parser verbatim on this section.

| Off | Type    | Field |
|-----|---------|-------|
| 0   | u8      | `version` (= 11) |
| 1   | u8      | `soc_percent` (filtered) |
| 2   | u16 LE  | `voltage_mV` |
| 4   | i16 LE  | `current_mA` (negative = discharging) |
| 6   | u16 LE  | `remaining_mAh` |
| 8   | u16 LE  | `full_charge_mAh` |
| 10  | i16 LE  | `temperature_0_1K` (÷10 then −273.15 for °C) |
| 12  | u16 LE  | `flags_raw` |
| 14  | u16 LE  | `control_status_raw` |
| 16  | u8      | `status_bits` (bit0 charging, 1 full, 2 low, 3 critical, 4 bat_detected, 5 qmax_learned, 6 res_learned, 7 itpor) |
| 17  | u8      | `soc_unfiltered` |
| 18  | u16 LE  | `design_capacity_mAh` — iOS expects **300** |
| 20  | u16 LE  | `terminate_voltage_mV` — iOS expects **3000** |
| 22  | u16 LE  | `taper_rate` — iOS expects **100** |
| 24  | u16 LE  | `op_config_raw` — iOS expects **0x6458** |
| 26  | i16 LE  | `average_power_mW` |
| 28  | i8      | `board_offset` — iOS flags |x|>5 |
| 29  | u8      | `deadband_mA` — iOS expects **5** |
| 30  | u8 × 16 | `calib_bytes` (Subclass 104 dump) |
| 46  | u8      | `init_fail_stage` (0 = ok) |
| 47  | u8      | `init_completed` (1 = ok) |
| 48  | u8      | `post_reset_fired` (1 = ok) |
| 49  | u16 LE  | `chem_id_read` — iOS expects **0x3230** |

**Suspected wrong (please confirm or correct):**

1. **OpConfig SLEEP bit.**
   The iOS app currently treats **bit 5 (mask 0x0020)** of `op_config_raw`
   as the SLEEP-enable bit and warns on it being set. Is that the right
   bit? Per TI BQ27427-G1A datasheet OpConfig wiring, SLEEP can sit in
   different bit positions across BQ family parts. Please give:
   - the exact bit position used by the BQ27427 firmware revision running
     on production WatchDog units, and
   - the expected polarity (1 = sleep enabled = bad, or inverted?).

2. **`chem_id_read` expected value.**
   The iOS app expects `0x3230`. This came from the legacy `BatteryDiagnostic`
   parser. Is `0x3230` still the chem ID you're shipping, or has it
   changed to a different profile? If different, please give:
   - the current expected `chem_id_read`, and
   - the meaning of any other values we might see in the field.

3. **`init_completed` / `post_reset_fired`.**
   App treats `init_completed == 1` as healthy and `post_reset_fired == 1`
   as healthy. Confirm — or do these fields encode more than a boolean?

4. **`init_fail_stage` codes.**
   The app maps stages 0..12 from the legacy parser (see
   `BatteryDiagnostic.describeInitFailStage`). Has the firmware added new
   stages, renamed any, or changed an ordinal?

5. **Status bits 0..7.**
   The bit assignments (charging / full / low / critical / bat_detected /
   qmax_learned / res_learned / itpor) — confirm these match the current
   firmware, especially `qmax_learned` vs. `res_learned` ordering, since
   those have been swapped in some past revisions.

6. **`flags_raw` bits 14/15** treated as undertemp (bit 14) and overtemp
   (bit 15). Confirm.

---

## `0x03` BLE (currently 14 bytes)

| Off | Type   | Field |
|-----|--------|-------|
| 0   | i8     | `current_rssi_dBm` (0x7F sentinel = not measured this build) |
| 1   | u16 LE | `connection_count_since_boot` |
| 3   | u8     | `last_disconnect_reason` (HCI error code) |
| 4   | u16 LE | `mtu_negotiated` |
| 6   | u16 LE | `connection_interval_units` (1.25 ms units; 0 = not measured) |
| 8   | u8 × 6 | reserved (zero) |

**Questions:**

1. iOS classifies HCI codes 0x13/0x16 as user-terminated (info), 0x08/0x22/0x3E
   as timeout/failure (warn). Are there other codes the firmware is likely
   to surface (e.g. 0x05 auth failure, 0x3D MIC failure) that we should
   special-case?

2. Is `current_rssi_dBm` actually populated in the production build, or is
   it still the 0x7F sentinel? Same question for `connection_interval_units`.

---

## `0x04` SENSOR (currently 18 bytes)

| Off | Type   | Field |
|-----|--------|-------|
| 0   | u8     | `cached_mlc_state` (0x00 STATIONARY_UPRIGHT, 0x04 STATIONARY_NOT_UPRIGHT, 0x08 IN_MOTION, 0x0C SHAKEN, else unknown) |
| 1   | u8     | `last_fsm_event` (0 = none, else FSM event code: impact / freefall) |
| 2   | u32 LE | `mlc_transitions_since_boot` |
| 6   | u32 LE | `int1_fires_since_boot` |
| 10  | u32 LE | `motion_events_logged_since_boot` |
| 14  | u8 × 4 | reserved (zero) |

**Questions:**

1. App's `MLCState` enum (used elsewhere) defines `doorOpen = 1`, `inMotion
   = 2`, `shaken = 3`, `stabilizing = 0xFE`, `unknown = 0xFF` — i.e. the
   raw values used in DEVICESTATUS frames don't match the four cached MLC
   states above (0x00 / 0x04 / 0x08 / 0x0C). Are these intentionally
   different encodings (raw MLC register vs. derived enum), or should the
   diagnostic section report the same 0..3 + 0xFE encoding as the live
   status frames?

2. `last_fsm_event` event code list — please enumerate every value the
   firmware can emit (impact, freefall, others?).

---

## `0x05` POWER (currently 24 bytes)

| Off | Type   | Field |
|-----|--------|-------|
| 0   | u32 LE | `wakes_motion`  (PB15 / accel INT1) |
| 4   | u32 LE | `wakes_cable`   (PB4 plug) |
| 8   | u32 LE | `wakes_debug`   (PB5 debug-hold) |
| 12  | u32 LE | `wakes_tick`    (everything else) |
| 16  | u32 LE | `time_in_lp_seconds` |
| 20  | u8     | `current_power_state` (0 active, 1 LP_IDLE, 2 LP_ARMED) |
| 21  | u8 × 3 | reserved (zero) |

**Questions:**

1. iOS computes sleep duty as `time_in_lp_seconds / uptime_seconds` and
   flags duty <50 % as bad, 50–90 % warn, ≥90 % ok. Is that the right
   threshold for a healthy idle WatchDog, or should we expect higher
   (e.g. ≥99 %)?

2. Is `LP_IDLE` vs `LP_ARMED` the right naming? Is there a third LP mode
   (e.g. shipping mode) we should expect to see?

---

## `0x06` STORAGE (currently 26 bytes)

| Off | Type   | Field |
|-----|--------|-------|
| 0   | u16 LE | `motion_log_count` |
| 2   | u16 LE | `motion_log_max` (currently 169 = `MAX_MOTION_EVENTS`) |
| 4   | u8     | `loyalty_store_healthy` (1 healthy, 0 = ALL loyalty ops refused) |
| 5   | u8     | `loyalty_claimed` (1 claimed, 0 unclaimed) |
| 6   | u32 LE | `i2c_errors_since_boot` |
| 10  | u32 LE | `eeprom_fail_count` |
| 14  | u32 LE | `bq27427_fail_count` |
| 18  | u32 LE | `lis2dux12_fail_count` |
| 22  | u8 × 4 | reserved (zero) |

**Questions:**

1. Is `motion_log_max` really fixed at 169, or do some hardware variants
   have larger ring buffers?

2. Are the four `*_fail_count` fields cumulative since boot only (matching
   `i2c_errors_since_boot` semantics), or are some persisted across boots?

3. Are there any error counters that *don't* increment when they should
   (e.g. silent failures we should be more worried about)?

---

## Open process questions

1. **Section-mask byte.** iOS sends `[0xF4, 0xFF]` to request all sections.
   Is the request shape stable, or should we expect a future change to
   `[0xF4, mask, …extra params…]`? Want to know whether to keep a single-
   byte mask or pad.

2. **Atomic snapshot.** Within a single TLV blob, are all sections sampled
   at the same instant (e.g. one HAL-tick boundary)? If sections are
   sampled at different times, please document the worst-case skew so we
   can decide whether to surface "captured at" per-section.

3. **Firmware-side rate limiting.** iOS now polls at 1 Hz from the
   diagnostic view. The spec note says firmware caches battery state on a
   1 s tick. Is 1 Hz comfortable for the firmware, or do we risk wedging
   the BLE TX queue if we push faster (or in the background)? Should we
   back off automatically while charging / in LP mode?

4. **Future extensions.** The spec called out: hardfault PC/LR snapshot,
   BLE supervision-timeout count, per-state power-mode dwell histograms,
   motion-log overflow flag, EEPROM CRC mismatch counter, last sleep
   entry/exit timestamps. Which of these are likeliest to land first so
   the iOS app can pre-reserve UI rows and avoid a layout reshuffle later?

---

## Reply format

Easiest to digest if you reply with one bullet per question:

```
SYSTEM
- init_bitmask bit 7: <reserved/used — confirm>
- reset_cause bit positions: OK / WRONG: <correction>

BATTERY
- OpConfig SLEEP bit: WRONG. Correct bit is <N>, mask <0xNNNN>. Polarity: <…>
- chem_id_read expected: WRONG. Correct value <0xNNNN>, meaning <…>
- status_bits qmax/res ordering: <…>
…
```

Where the iOS expectation matches firmware, just say `OK` for that bullet.
Where it's wrong, give us the correct value plus, if relevant, the
firmware revision that introduced the change so we can version-gate.
