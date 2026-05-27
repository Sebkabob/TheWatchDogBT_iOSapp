# App Review Response — Submission 39972915-aeca-4ffc-a532-349dca125b60

Reply to send back through App Store Connect, plus the rationale behind each fix.

**Chosen approach:**

| Field | Value |
|---|---|
| App Store name (30 char) | `WatchDog BT: Bag Theft Alarm` (28/30) |
| Subtitle | `Anti-theft alarm for your bag` (unchanged) |
| `CFBundleDisplayName` (home-screen label) | `WatchDog BT` (11 chars — fits without truncation) |

---

## Why each rejection happened

### 4.1(a) — Copycats

The reviewer didn't name the conflicting app, but the App Store has at least six live apps using "Watchdog"/"WatchDog" in the title, and one uses the *exact* title pattern the previous listing did:

| Existing app | App Store ID | Why it likely triggered the flag |
|---|---|---|
| **WatchDog: Safety Check-In** | 6759113881 | Same "WatchDog: <descriptor>" pattern as the old "WatchDog: Bag Theft Alarm". Strongest match. |
| **WatchDog Mobile** (Spectrum Technologies) | 1451317013 | Established Bluetooth/IoT device companion app — same category. |
| **Watchdog** | 1447184496 | Bare "Watchdog" — collided head-on with the old `CFBundleDisplayName = WatchDog`. |
| **WatchDog – Home Guard by iPhone** | 1084157847 | Home-security framing, adjacent category. |
| **ID Watchdog** (Equifax) | 1227744009 | Big brand, "Watchdog" in name. |
| **Digital Watchdog** | dev id 396640283 | Surveillance/security camera ecosystem. |

The Ubisoft **Watch Dogs** franchise (with the `ctOS Mobile` companion) exists but is less likely to be the trigger — different spelling, different category.

"WatchDog" is a generic English word, so there's no exclusive trademark to claim. The realistic fix is to differentiate, which is what the changes below do — leaning on the `BT` suffix that's already the hardware brand (visible in the repo `TheWatchDogBT_iOSapp`, in the asset files `WatchDogBT_*.usdz`, and in code symbols like `WatchDogFirmware`).

### 2.1 — Information Needed (demo video)

The reviewer wants three concrete things:

1. App running on a **physical** iPhone or iPad (not a simulator).
2. The **initial pairing** between the app and the WatchDog BT hardware, end-to-end.
3. The **entire app workflow** with the hardware visible in frame.

Shoot list (60–90 seconds, single take is fine):

1. Tripod or second device pointed at both the iPhone/iPad **and** a WatchDog BT unit in the same frame the whole time.
2. **Fresh install** — delete the app first so the reviewer sees a cold-start pairing flow.
3. Launch app → "Add a WatchDog" → scan list populates → tap your device → on-device LED reacts → bond completes on phone.
4. Device page → arm → lift/shake the hardware → in-app alert + on-device alarm fire → tap to disarm.
5. Motion Log → show the timestamped event from step 4.
6. Settings for the device → flip one preset (e.g., sensitivity) → close.
7. Unpair from the app.

Hosting: unlisted YouTube is the easiest. Put the link in **App Review Information → Notes** *and* paste it into the reply below.

The existing in-app demo mode is fine to keep as a fallback for reviewers without hardware, but it does not satisfy 2.1 — the reviewer is explicitly asking for the real hardware interaction.

Optional but recommended: also offer to ship a review unit via Apple's [review-attachment / hardware request form](https://developer.apple.com/contact/app-store/review-attachment/). Mentioning the offer in the reply signals good faith even if Apple doesn't take you up on it.

---

## Reply to paste into App Store Connect

Fill in the one `[PASTE YOUR VIDEO URL]` placeholder before sending.

```
Hi App Review,

Thank you for the detailed feedback. We have addressed both items.

Guideline 2.1 — Demo video

We have recorded a new walkthrough on a physical iPad (not a simulator)
that keeps the WatchDog BT hardware in the same frame as the device
throughout. The video covers:

  • A fresh install and the initial pairing flow between the app and the
    hardware (scan → discover → bond → LED confirmation on the device)
  • Arming the device, triggering motion on the hardware, and the
    resulting in-app alert plus on-device alarm
  • Reviewing the timestamped motion log
  • Adjusting a sensitivity preset in the device settings
  • Unpairing the device

Link (unlisted): [PASTE YOUR VIDEO URL]

We have also updated the demo notes in App Review Information. If it would
help your evaluation, we are happy to ship a review unit of the hardware
to Apple via the review-attachment request form — please let us know.

Guideline 4.1(a) — Copycats

To remove any possibility of confusion with existing apps using "WatchDog"
in their title, we have differentiated the brand throughout the listing
and the binary:

  • App name updated to: "WatchDog BT: Bag Theft Alarm"
  • Home-screen name (CFBundleDisplayName) updated to: "WatchDog BT"
  • Description updated to lead with the "WatchDog BT" brand and to make
    the Bluetooth-hardware nature of the product unambiguous in the
    opening paragraph
  • Screenshot captions updated to reflect the new branding

"WatchDog BT" is our own product brand — it is also the model name of the
companion hardware device and is reflected in our project assets and
repository (TheWatchDogBT_iOSapp). The app is the exclusive companion to
this hardware and is published by the same party that produces the device.

The updated build and metadata are attached in this resubmission.

Thank you for the review,
Sebastian Forenza
```

---

## Pre-resubmit checklist

- [x] `INFOPLIST_KEY_CFBundleDisplayName = "WatchDog BT"` in `project.pbxproj` (Debug + Release) — *done in this session*
- [x] In-app About-screen header updated from `Text("WatchDog")` to `Text("WatchDog BT")` in `App/MainAppView.swift` — *done in this session*
- [x] `AppStoreListing.md` updated — App Store name, promotional text, description, "What's New" all now use `WatchDog BT` for the brand mentions — *done in this session*
- [ ] App Store Connect → App Information → **Name** field updated to `WatchDog BT: Bag Theft Alarm`
- [ ] App Store Connect → updated promotional text, description, and "What's New" pasted from `AppStoreListing.md`
- [ ] At least one screenshot's overlay text uses `WatchDog BT`
- [ ] Demo video recorded, uploaded as unlisted, link added to App Review Information **and** the reply above
- [ ] Build number incremented — previous submission was `1.0 (2)`, the resubmission needs to be `1.0 (3)` or higher
- [ ] (Optional) If you ever register a "WatchDog" or "WatchDog BT" trademark, attach the certificate PDF in App Review Information for future submissions

## What we deliberately did *not* change

- **In-app strings that refer to the hardware as "WatchDog"** (e.g., `"WatchDog is not connected."`, `"Couldn't reach this WatchDog. Try again."`, `"Add a WatchDog"`). These read naturally and the hardware itself is colloquially "your WatchDog" in user-facing copy. Apple's 4.1(a) flag is about *listing metadata* (App Store name, subtitle, description, screenshots) and the *home-screen label* (`CFBundleDisplayName`) — both of which now say "WatchDog BT". Re-spelling every internal string would mean a much larger localization sweep across 6 languages for diminishing returns.
- **`AppStoreListing.md` keyword field.** The keyword list (`backpack,luggage,bike,travel,bluetooth,tracker,motion,security,laptop,purse,suitcase,find,locator`) does not contain "watchdog" already, so nothing to change.
- **Repo name, bundle ID, asset file names.** Renaming `Sebkabob.WatchDog-iOS` or the on-disk project folder is high-risk and unrelated to the rejection. The bundle ID is invisible to App Review.
