# WatchDogBT — power optimisation pass (prompt for firmware Claude Code)

## Context

The device currently averages **104 µA** while disconnected and advertising at the LP interval (1 s). A previous build hit **33 µA** on the same hardware, so the chip-level floor is reachable — the gap is firmware-configurable. Deep research has decomposed the budget across every chip on the board; this is the implementation plan.

You're working on the `V2` branch. The hardware is unchanged; we're only touching firmware.

## Rules (do not skip)

1. **Read `CLAUDE.md` first.** Honour the version-bump procedure exactly:
   - Recompute `MAIN` from `git rev-list --count --first-parent main` and `V2` from `git rev-list --count main..V2`.
   - For each commit you land on `V2`, increment `V2` by 1 and bake it into `firmware_version.h` + the `Current: V…` line in `CLAUDE.md` in the same commit.
   - Commit message style: `version bump to Vx.y.z`.
2. **`ONLY EDIT CODE WITHIN THE USER EDITABLE SECTIONS!!!`** — for CubeMX-generated files, only inside `USER CODE BEGIN/END` blocks.
   - `app_conf.h`: the `CFG_BLE_*` defines live outside USER CODE blocks but are conventionally edited directly. Note in your commit message that a CubeMX regen would clobber them so anyone running CubeMX should mirror these in the `.ioc`.
   - `main.c`: the `LL_PWR_DisableDBGRET()` call goes inside `/* USER CODE BEGIN 2 */`.
3. **One change per commit.** Each commit should land an isolated optimisation so a future bisect can identify which one regressed if power goes up. Bump V2 each commit.
4. **Update `CLAUDE.md` "Current Vx.y.z" + reconciled-sha** in the same commit as the firmware-version header bump. Don't drift.
5. **Don't refactor.** Don't rename, don't reformat, don't restructure. Each commit is a minimal diff.
6. **After all commits, write a short summary** of what landed, what you didn't (and why), and the expected µA savings.

## Implementation order

Do them in this order — easy / high-confidence first, riskier last. After each commit, the user will measure with a Power Profiler Kit; if a commit unexpectedly *increases* current it gets reverted.

---

### Commit 1 — disable SWD/debugger retention in DEEPSTOP

**File:** `Core/Src/main.c`

In the `/* USER CODE BEGIN 2 */` block (after `BUZZER_Init()` and the I2C/EEPROM rail bring-up, before `MX_APPE_Init`), or in `/* USER CODE BEGIN WHILE */` immediately before the `while (1)` — wherever fits cleanly without disturbing existing code:

```c
/* SWD/debug retention across DEEPSTOP costs ~5–10 µA on STM32WB0 (PA2/PA3
 * stay clamped by the PWR controller). Production builds don't need
 * SWD-attach across sleep, so disable retention. To debug a sleeping unit,
 * comment this single call out for that build only. */
LL_PWR_DisableDBGRET();
```

**Verify:**
- Builds clean.
- Device still wakes from cable plug and motion.
- SWD attach during ACTIVE state still works (only retention across DEEPSTOP is affected).

**Expected saving:** 5–10 µA.

---

### Commit 2 — strip unused BLE stack features (SRAM retention)

**File:** `Core/Inc/app_conf.h`

Reduce the BLE stack's retained SRAM by zeroing buffers for features that are never enabled. Verify by printing `sizeof(dyn_alloc_a)` (defined in `STM32_BLE/App/app_ble.c`) before and after — should drop by several kB.

| Define | Old | New |
|---|---|---|
| `CFG_BLE_ATT_MTU_MAX` | 247 | 65 |
| `CFG_BLE_NUM_GATT_ATTRIBUTES` | 20 | 13 |
| `CFG_BLE_NUM_ADV_SETS` | 2 | 1 |
| `CFG_BLE_NUM_PAWR_SUBEVENTS` | 16 | 0 |
| `CFG_BLE_PAWR_SUBEVENT_DATA_COUNT_MAX` | 8 | 0 |
| `CFG_BLE_NUM_AUX_SCAN_SLOTS` | 2 | 0 |
| `CFG_BLE_NUM_SYNC_SLOTS` | 1 | 0 |
| `CFG_BLE_NUM_SYNC_BIG_MAX` | 1 | 0 |
| `CFG_BLE_NUM_BRC_BIG_MAX` | 1 | 0 |
| `CFG_BLE_NUM_SYNC_BIS_MAX` | 1 | 0 |
| `CFG_BLE_NUM_BRC_BIS_MAX` | 1 | 0 |
| `CFG_BLE_NUM_CIG_MAX` | 1 | 0 |
| `CFG_BLE_NUM_CIS_MAX` | 1 | 0 |
| `CFG_BLE_FILTER_ACCEPT_LIST_SIZE_LOG2` | 3 | 1 |
| `CFG_BLE_USER_FIFO_SIZE` | 1024 | 256 |
| `CFG_BLE_ISR1_FIFO_SIZE` | 768 | 256 |
| `CFG_BLE_ISR0_FIFO_SIZE` | 256 | 128 |
| `CFG_BLE_COC_NBR_MAX` | 1 | 0 |
| `CFG_BLE_COC_MPS_MAX` | 23 | 0 |
| `CFG_BLE_NUM_EATT_CHANNELS` | 0 | 0 *(already correct, leave)* |

A few of these are guarded by `BLE_STACK_TOTAL_BUFFER_SIZE` math — if the build fails because some macro requires a non-zero value, set it to `1` instead of `0` and note that in the commit message.

**Verify:**
- Builds clean.
- Device advertises, connects, sends DEVICESTATUS (19 B) and BATTERYDIAG (51 B) notifications correctly.
- Pairing / loyalty token flow works end-to-end with the iOS app.
- Add a one-shot debug print of `sizeof(dyn_alloc_a)` near the top of `BLE_Init()` for the first commit only, to confirm the drop. Remove the print in a follow-up.

**Expected saving:** 8–15 µA.

---

### Commit 3 — drop CFG_TX_POWER from 0 dBm to −8 dBm

**File:** `Core/Inc/app_conf.h`

```c
#define CFG_TX_POWER  (0x0A)  /* -8 dBm — adv burst peak ~half of 0 dBm */
```

Update the inline comment on the same line to note the dBm value.

**Verify:**
- Phone still discovers the device from ~10 m line-of-sight.
- Connection establishment and notifications work normally.

**Expected saving:** 10–15 µA average (cuts TX peak roughly in half during the ~5 ms adv burst per 1 s window).

---

### Commit 4 — disable BQ27427 internal temperature ADC

**File:** `Core/Src/battery.c`, `Drivers/BQ27427/bq27427.c` (or wherever `bq27427_op_config` is mutated)

In `BATTERY_Init()`'s `needs_config` block, after `bq27427_enable_sleep()` and before `bq27427_exit_config(true)`, add a call to clear the OpConfig `TEMPS` bit (it controls internal temperature sampling — bit 11 on BQ27427, verify against the TI reference manual SLUUCD5 §Op Config).

Add a helper in `Drivers/BQ27427/` if one doesn't exist (`bq27427_disable_internal_temp()` or similar) — read OpConfig, clear the relevant bit, write back, then re-execute the CFGUPMODE checksum step. Don't add this if it requires touching auto-generated driver code; in that case do the read-modify-write inline in `battery.c` using existing `bq27427_op_config()` and the matching write helper.

**Verify:**
- `BATTERY_GetOpConfig()` in the BATTERYDIAG notification shows the TEMPS bit cleared.
- Battery SOC / voltage / current still update correctly.
- Internal temperature reads will go to 0 / invalid — that's expected and acceptable.

**Expected saving:** 1–2 µA.

---

### Commit 5 — verify and self-heal BQ27427 SLEEP_EN bit

**File:** `Core/Src/battery.c`

This is the single biggest expected win and the most likely cause of the 104 → 33 µA regression. The current `bq27427_enable_sleep()` call inside `BATTERY_Init()` returns success but never reads OpConfig back to confirm bit 5 (SLEEP) actually persisted.

Modify `BATTERY_Init()` so that after `bq27427_enable_sleep()` returns, the code:

1. Calls `bq27427_op_config()` to read OpConfig back.
2. Checks bit 5 (SLEEP) is set.
3. If not set, retries `enter_config → enable_sleep → exit_config` up to 3 times with a 200 ms delay between attempts.
4. If still not set after 3 retries, sets a new diagnostic stage (e.g. `s_init_fail_stage = 13`) and exposes it via the existing `BATTERY_GetInitFailStage()` accessor so the iOS app can see it in BATTERYDIAG.

Don't change the structure of `BATTERY_Init()` beyond this — keep the existing `s_init_fail_stage` codes intact and just add `13` as the new failure mode for "SLEEP bit failed to persist".

Also in `BATTERY_UpdateState()`, expose the BQ27427 ControlStatus's SLEEP bit (bit 4 of the high byte of CONTROL_STATUS, per SLUUCD5) into a new accessor `BATTERY_IsGaugeAsleep()` so iOS can see whether the gauge actually sleeps in field.

**Verify:**
- After init, OpConfig bit 5 reads high.
- After 30+ s of disconnected idle (gauge sees system current well under the 10 mA Sleep threshold), `BATTERY_IsGaugeAsleep()` reads true.
- Reconnect from iOS, read BATTERYDIAG, verify both bits are visible in the existing diagnostic payload (you may need to expand the payload by 1 byte — that's acceptable, just bump the layout-version comment in `lockservice_app.c` and update the iOS-side parser docs in a separate work item).

**Expected saving:** 0–41 µA. If the gauge was already in SLEEP this is a no-op; if it was stuck in NORMAL this alone closes the regression.

---

## After all commits

In a final summary message, report:

- The starting and ending firmware version (e.g. `V1.11.19 → V1.11.24`).
- For each commit: the SHA, the version, the headline change, and the expected µA saving.
- The before/after `sizeof(dyn_alloc_a)` numbers from commit 2.
- Anything you skipped, with the reason (build error, define gating, etc.).
- A reminder to the user to: (1) measure each commit on PPK, (2) read OpConfig over BLE to confirm SLEEP_EN persisted, (3) bisect from V1.11.19 if the cumulative saving is much smaller than expected (~25–80 µA).

Do **not** touch any of these — out of scope for this pass:

- Anything in `Drivers/`, `Middlewares/`, `STM32_BLE/Target/`.
- Generated CubeMX files outside their USER CODE blocks (other than `app_conf.h`, which is the convention).
- Schematic-level questions (PA10 IMU rail gating verification — that's a hardware probe task for the user).
- The state machine, accelerometer LP modes, EEPROM gating — already optimal.
- Forcing BQ27427 into SHUTDOWN (deferred — only if commits 1–5 don't get the device under 35 µA).
- Bumping ADV_LP_INTERVAL from 1 s to 2 s (deferred — UX trade-off, user-call).

Go.
