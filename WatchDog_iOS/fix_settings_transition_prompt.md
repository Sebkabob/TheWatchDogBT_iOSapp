# Fix the Home → Settings transition animation (DuoDog app)

## Problem

When tapping into the Settings screen from the main "DuoDog / Unlocked" home view, the device illustration (the long black dongle/whistle) slides to the right edge of the screen, but the transition feels clunky and "bumpy". A frame‑by‑frame analysis of a screen recording shows three concrete issues:

1. **Mid-transition stall.** The device's `translateX` slide finishes in roughly 120 ms (it reaches its final right‑edge resting position around frame 17 of 60). The cross‑fade between Home and Settings then runs for another ~150–200 ms. During that window the device sits frozen at the edge of a black screen with nothing else moving. That motionless plateau is the "bump" — the device hard‑stops, then everything else catches up.

2. **Decoupled siblings.** The speaker / volume button, the "Unlocked" status header, the battery readout, and the "Hold to Lock / Disconnect / Motion Logs" button row do **not** translate with the device. They just fade in place. As the device slides right you can briefly see it overlap the speaker icon, and the buttons sit static in their original positions while everything else moves. The transition reads as several independent animations rather than one coordinated motion.

3. **No matched motion from the incoming screen.** Settings simply fades in around the device's final position. There's nothing pushing the device out, so its only forward momentum dies at the edge.

Net effect: the device's translation duration and easing are not synchronized with the screen cross‑fade, and surrounding UI elements do not move with it. That mismatch is what makes the transition feel clunky.

## Goal

A single, coordinated, shared‑element transition where the device illustration moves continuously from its Home position to its Settings anchor over the same duration and easing curve as the screen change, with sibling elements either translating along with their parent screen or animating in/out in a way that supports (rather than fights) the device's motion.

## What to change

You don't have to keep the exact existing structure if it's getting in the way — feel free to refactor the transition into a single coordinated animation. The fix should hit all of the following:

### 1. Synchronize durations and easing
- Use **one** animation duration for the device translate and the Home→Settings transition. Target ~320–360 ms.
- Use a single easing curve for both, ideally `easeInOut` (e.g. `Animation.easeInOut(duration: 0.34)` in SwiftUI, or a `UIView.AnimationCurve.easeInOut` / `CASpringAnimation` with low bounce in UIKit).
- The device must still be in motion at the moment the new screen finishes fading in. No "device arrives, then screen catches up."

### 2. Make the device a shared / matched‑geometry element
- In SwiftUI, use `matchedGeometryEffect(id: "device", in: namespace)` on the device view in **both** the Home screen and the Settings screen, with a shared `@Namespace` declared on the parent that hosts the navigation.
- In UIKit, use a custom `UIViewControllerAnimatedTransitioning` that snapshots the device view from the source VC, animates a single shared `UIImageView` from its Home frame to its Settings frame, and reveals the destination VC's device view at the end.
- The same device view animates from its Home position (centered horizontally, vertically positioned with the dotted speaker pattern around the lower third) to its Settings anchor (right edge, partially clipped) in one continuous motion. There should never be two device views on screen at once during the transition.

### 3. Don't leave siblings behind
Pick one of these two coordinated approaches and apply it consistently:

**Option A — Translate the home content as a group.** Group the header ("DuoDog / Unlocked / battery"), the speaker button, and the bottom button row into a single container. Animate that container's `opacity` from 1 → 0 *and* a small `translateX` (e.g. -24 pt) over the same duration. They leave together, in one direction, while the device flies past them.

**Option B — Push from the side.** Have Settings slide in from the left (or fade + slight left‑to‑right offset) while Home slides off to the right with the device. The device's motion then reads as part of the page push.

Either way, the speaker button must not sit static while the device slides over it. If keeping the speaker static is intentional (because it's a global control), make it fade out *before* the device reaches it, not while overlapping it.

### 4. Soften the device's arrival
- Replace the hard stop at the right‑edge anchor with a gentle settle. Either:
  - Use `easeInOut` instead of `easeOut`, so the device decelerates symmetrically, OR
  - Add a small spring at the end (`response: 0.45, dampingFraction: 0.85` in SwiftUI's `.spring`) — subtle, not bouncy.
- Avoid any keyframe where the device's velocity drops to 0 before the screen transition finishes.

### 5. Verify
After the change, record the transition again and confirm:
- The device is still moving (non‑zero velocity) at the frame the Settings labels become fully opaque.
- The speaker icon is never visually overlapped by the moving device.
- There are not two device views visible at any single frame.
- The total transition duration is ~300–400 ms and feels like one motion, not three.

## Suggested SwiftUI sketch

```swift
struct AppRoot: View {
    @Namespace private var deviceNS
    @State private var screen: Screen = .home

    var body: some View {
        ZStack {
            switch screen {
            case .home:
                HomeView(deviceNS: deviceNS, onOpenSettings: { 
                    withAnimation(.easeInOut(duration: 0.34)) { screen = .settings } 
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal:   .opacity.combined(with: .move(edge: .leading))
                ))
            case .settings:
                SettingsView(deviceNS: deviceNS, onBack: { 
                    withAnimation(.easeInOut(duration: 0.34)) { screen = .home } 
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal:   .opacity.combined(with: .move(edge: .trailing))
                ))
            }
        }
    }
}

// In both HomeView and SettingsView:
DeviceImage()
    .matchedGeometryEffect(id: "device", in: deviceNS)
```

Key points: one namespace, one `withAnimation` block, one duration, one easing curve. The device's position change is driven entirely by `matchedGeometryEffect` reacting to its different layout in `HomeView` vs `SettingsView` — not a separate `.offset` animation.

## Files most likely to touch
- The view(s) that render the home "Unlocked" screen and the Settings screen (look for "Hold to Lock", "Forget Device", "DuoDog").
- The navigation / routing layer that swaps between them.
- Any custom `UIViewControllerAnimatedTransitioning` if this is UIKit, or the `@Namespace` host if SwiftUI.
- Wherever the device illustration view is defined — it needs a `matchedGeometryEffect` modifier (SwiftUI) or to be reachable as a snapshot source (UIKit).

## Out of scope
- Don't change the visual design of either screen (colors, copy, button styles).
- Don't change what Settings contains.
- Don't change Home's idle layout.
Only the transition between them should change.
