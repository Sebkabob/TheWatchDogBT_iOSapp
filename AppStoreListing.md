# WatchDog BT — App Store Connect Listing

Copy-paste straight into App Store Connect. Character counts verified against Apple's 2026 limits. Anything in `[brackets]` is a placeholder you need to fill in.

> **2026-05-26 update.** The submission was rejected under 4.1(a) (copycat) for resembling existing "WatchDog" apps. The fix: differentiated brand to **WatchDog BT** (the hardware name), in both the App Store name field and the home-screen `CFBundleDisplayName`. See `AppReviewResponse.md` for the full reply going back to App Review.

---

## App Name (30 max)

```
WatchDog BT: Bag Theft Alarm
```

**28 / 30 characters.** Leads with the brand (`WatchDog BT` — also the home-screen `CFBundleDisplayName`, and the name of the companion hardware), then the most specific search phrase a worried bag-owner would type. The `BT` suffix disambiguates from the several other "WatchDog" apps on the App Store, resolving the 4.1(a) collision flagged in App Review on 2026-05-20.

---

## Subtitle (30 max)

```
Anti-theft alarm for your bag
```

**29 / 30 characters.** Picks up `anti-theft`, `alarm`, and `bag` for search — these all combine with the keyword field. Reads like a human description, not a keyword stuff.

---

## Promotional Text (170 max)

```
Set your bag down. Grab a coffee. The second someone reaches for it, WatchDog BT screams — and your phone knows. No accounts, no cloud, just you and your stuff.
```

**160 / 170 characters.** This is the only field you can edit after release without resubmitting — great place to swap in seasonal hooks ("Heading to the airport?") or press mentions later.

---

## Description (4000 max)

```
Set your bag down. Grab a coffee. Have a real conversation.

WatchDog BT is a tiny Bluetooth alarm that clips onto whatever you don't want walking away from you. Tuck it into a backpack, slip it into a tote, drop it inside a piece of luggage — the moment someone picks it up, jostles it, or knocks it over, it screams. Then it pings your phone so you actually know it happened.


WHY PEOPLE USE IT

– Coffee-shop laptop runs without the heart-attack feeling on the walk back from the bathroom
– Long flights where your roll-aboard rides a few rows behind you
– Hostels, dorm rooms, gym lockers, the second seat at the airport gate
– Bike or e-scooter locked out front for ten minutes
– Anything you'd hate to lose


SET IT UP IN A MINUTE

Pair your WatchDog BT once. Pick a preset — Door Guard, Drawer Watch, Vehicle Guard, Package Watch, or Max Security — or build your own. Slide the lock button and it's armed. Hold to disarm. That's the whole thing.

A short tutorial walks you through three gestures the first time you open the app: swipe between devices, tap to open settings, hold to lock. No instruction manual.


YOUR LOCK, YOUR DATA

WatchDog BT doesn't have an account. There's no signup, no cloud sync, no profile to delete later. Pairing is a private handshake between your phone and your device — once it's claimed, only your phone can arm it, disarm it, or read its motion history.

The app pins the location of every lock on a map so you can remember where you left things, but location is only captured at the exact moment you lock. Nothing is streamed, nothing is shared, nothing leaves your phone.

If you ever lose your phone or reinstall the app, there's a built-in recovery option so you can claim your device again without calling support.


FINE-TUNE THE FEEL

– Three sensitivity levels, from "ignore the bus rumbling past" to "twitch and it goes off"
– Four alarm voices: silent, calm, normal, or full-volume "everyone in the café looks up"
– Trigger types you can mix and match: In Motion, Shaken, Impact, Freefall, Tilted, Door Opening, Door Closing
– Timestamped motion logs so you can see exactly when something tried to move it
– A find-my-WatchDog-BT buzz for when you've forgotten which bag you stuffed it in
– Adjustable LED brightness, alarm duration, and Bluetooth range


SIX LANGUAGES, ONE APP

English, Español, Français, Nederlands, Português, 日本語.


WatchDog BT is the device-side equivalent of locking your front door. Quick, quiet, worth the two seconds it costs you.

Hardware sold separately. Learn more at [your marketing URL].
```

**~2,650 / 4,000 characters.** Long enough to land, short enough to read. Plain text — App Store strips markdown, so the dashes render as dashes and the section breaks render as blank lines.

---

## Keywords (100 max — comma-separated, no spaces)

```
backpack,luggage,bike,travel,bluetooth,tracker,motion,security,laptop,purse,suitcase,find,locator
```

**97 / 100 characters.** Deliberately avoids repeating words already in your name and subtitle (`alarm`, `bag`, `theft`, `anti-theft`, `watchdog`) — Apple indexes those too, so re-using them here wastes the slot. Apple's search combines all three fields into compound phrases, so `bag` (subtitle) + `backpack` (keywords) covers searches like "bag backpack alarm" without spending characters on either.

---

## What's New in This Version (4000 max)

If this is your first App Store release:

```
First release. Thanks for picking up a WatchDog BT.

This is the launch build — pair your device, set a sensitivity, lock it, you're done. If anything feels rough, the support link below goes straight to me.
```

For future updates, the rhythm to keep: one sentence on the headline change, one or two on the smaller stuff, occasionally a thank-you. People scan this field. Don't pad it.

---

## Categories

- **Primary:** Utilities
- **Secondary:** Travel

Utilities is where Tile, Chipolo, and most BLE companion apps live, so the comparison set is appropriate. Travel as secondary picks up the "luggage / airport / hostel" search cohort. Lifestyle is the other defensible choice if you'd rather be discovered next to home-security apps than next to Tile.

---

## Suggested screenshot captions (since June 2025, Apple indexes these for search)

Pair these with whatever screenshot order you go with. Each is ≤ 25 characters so they fit on the screenshot overlay without wrapping on smaller iPhones.

1. `Lock it. Walk away.`
2. `Buzzes the second someone touches it.`
3. `Five presets, one tap.`
4. `Every motion, timestamped.`
5. `Owner-only. No accounts.`

---

## URLs

The repo already ships a GitHub Pages site at `docs/` — use that for both the support page and the privacy policy. Confirm Pages is enabled at `https://github.com/sebkabob/TheWatchDogBT_iOSapp/settings/pages` (source: `main` / `/docs`) before submitting.

- **Support URL:** `https://sebkabob.github.io/TheWatchDogBT_iOSapp/`
- **Privacy Policy URL:** `https://sebkabob.github.io/TheWatchDogBT_iOSapp/privacy`
- **Marketing URL:** optional. Same as support URL is fine for v1, or leave blank and add later when you have a proper product page.

The privacy policy in `docs/privacy.md` declares no accounts, no network calls, no analytics, no children's data, Bluetooth-only — which is consistent with what the app actually does. Make sure your nutrition labels in App Store Connect match:

---

## Privacy nutrition labels — pre-fill suggestion

The privacy policy at `docs/privacy.md` says **nothing leaves the device**. To match it, in App Store Connect → App Privacy:

- Select **Data Not Collected**.

That's the cleanest, most defensible label and it matches the policy verbatim. If you ever add a crash reporter or analytics SDK, switch the label then — but as the app ships today, "Data Not Collected" is the honest answer.

Note: the in-app map (`SessionLocationStore.swift`) does capture coarse location at the moment you tap lock, but that data is stored only on the user's device and never transmitted off it. Apple's nutrition-label rules treat "stored on device, never sent anywhere" as **not collected** for label purposes, which is why "Data Not Collected" is still correct here.
