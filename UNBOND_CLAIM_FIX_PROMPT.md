# iOS coordination: post-UNBOND CLAIM fix

## Context

There's a "Forget Device" → re-pair bug. From the user's POV: tap Forget, tap to re-pair from the same iPhone, see "Not your device!". The root cause is firmware-side, not iOS-side — the firmware's CLAIM dispatcher rejects a fresh claim when the device is unclaimed AND the USB-C reset window is closed. The firmware Claude Code instance is fixing that in `STM32_BLE/App/lockservice_app.c::LOCKSERVICE_Notification` (its prompt is at `TheWatchDogBT/UNBOND_CLAIM_FIX_PROMPT.md`).

After the firmware fix, an unclaimed device accepts CLAIM unconditionally; an already-claimed device still requires the USB-C reset window to be **overwritten**.

## What the iOS side has to do

**No behavioral code change is required.** The unbond flow, BondManager teardown, and CLAIM-vs-VERIFY selection are all already correct. The work here is verification + a comment refresh.

### 1. Verify the existing flow before assuming it's right

Read these and confirm:

- `WatchDog_iOS/Managers/BluetoothManager.swift` — `unpairDevice` (~714), `unpairDeviceWhileDisconnected` (~749), `finishUnpair` (~788), `clearLocalStateAfterUnpair` (~999). Confirm bond removal happens synchronously on the main thread before any reconnect can race.
- `WatchDog_iOS/Managers/BluetoothManager.swift::startLoyaltyHandshake` (~815–843). Confirm `isFirstClaim = !BondManager.shared.isBonded(...)` is computed at write-time, not connect-time, so a just-removed bond results in CLAIM (not VERIFY).
- `WatchDog_iOS/Managers/BluetoothManager.swift::handleReject` (~897–922). The `wasBonded ? "reset, tap again" : "Not your device!"` split — keep both branches as-is. Once the firmware fix is in, the legitimate post-unpair re-pair path returns CLAIM_OK and never reaches `handleReject`.

### 2. Refresh stale wording

The inline comment in `startLoyaltyHandshake` (around lines 823–826):

> Re-read bond state at the latest possible moment. If we just unpaired, BondManager will already reflect the removal. A stale isBonded() value would cause us to send VERIFY against an empty EEPROM and get REJECTed — the reported re-pair-after-unpair bug.

The "stale `isBonded()` → VERIFY → REJECTed" failure mode wasn't actually the only path that hit the bug. Even with a correct CLAIM, the firmware was rejecting until the firmware-side fix landed. Reword to roughly:

> Re-read bond state at the latest possible moment. If we just unpaired, BondManager will already reflect the removal. A stale `isBonded()` value would cause us to send VERIFY against an empty EEPROM and get REJECTed. (Sending CLAIM on an unowned device is also handled correctly by the firmware as of FW Vx.y.z — see TheWatchDogBT/UNBOND_CLAIM_FIX_PROMPT.md.)

Fill in the firmware version once the firmware commit lands (the firmware instance will write it into its own `CLAUDE.md`).

If you spot any other comment that implies post-UNBOND re-pair from the same iPhone needs USB-C, update it too.

### 3. End-to-end validation (after a firmware build with the fix is on a unit)

Manually exercise these:

- **Same-phone re-pair.** Pair → Forget → tap to re-pair (no cable). Expect: CLAIM_OK, bond restored, all settings round-trip cleanly. *(This is the bug under repair.)*
- **Different-phone takeover, no cable.** Pair on phone A → keep cable disconnected → try to pair from phone B. Expect: REJECT, "Not your device!" alert. *(The reset-window gate must still hold for an already-claimed device.)*
- **Different-phone takeover with USB-C window.** Plug cable on phone A's device → from phone B, tap Pair within 10 s. Expect: CLAIM_OK, ownership transfers. *(Existing recovery story for genuine takeover.)*
- **Cable-hold 30 s recovery hatch.** Hold cable plugged at boot for 30 s. Expect: distinct ascending tone, EEPROM wiped, any phone can claim. *(Unchanged.)*
- **Keychain wipe (app reinstall).** Delete app → reinstall → connect to existing claimed device. Expect: still requires USB-C reset window. (Same as before — the firmware fix only affects unclaimed devices, and Keychain-wiped iPhone faces an *already-claimed* device.)

### 4. Version bump

Per `CLAUDE.md`, follow the version recompute. If this is a `dev` commit: +1 to `AppVersion.v2`. If it lands on `main`: +1 to `MAIN`, reset `V2` to `0`. Update `AppVersion.swift` and the `Current: V…` + reconciled-sha line in `CLAUDE.md` in the same commit. Commit message: `version bump to Vx.y.z`.

If this turns out to be comment-only and you're not making a separate commit for it (e.g. waiting to bundle with the next dev change), don't bump.

## Don't touch

- The CLAIM/VERIFY/UNBOND opcodes or response codes (`0xC0`/`0xC1`/`0xC2`/`0xE4`/`0xE7`/`0xE8`/`0xE9`).
- `LoyaltyTokenStore` Keychain logic.
- `BondManager`'s storage layer.
- The reject alert text — both branches stay; they just become correctly attributed once the firmware fix is live.
