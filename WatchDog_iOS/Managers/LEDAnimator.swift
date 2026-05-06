//
//  LEDAnimator.swift
//  BluetoothTesting
//

import Foundation
import UIKit
import Observation

/// Full LED state machine that mirrors the WatchDog firmware lighting logic.
/// Drive it by setting the input properties; read outputColor + outputIntensity each frame.
@Observable
class LEDAnimator {

    // MARK: - Output (read by SceneView3D)

    var outputColor: UIColor = .black
    var outputIntensity: Double = 0.0

    // MARK: - Input state (set by Motion3DView from BLE)

    var isFindMyActive: Bool = false
    var isCablePlugged: Bool = false
    var isCharging: Bool = false
    var isBatteryFull: Bool = false
    var isAlarmActive: Bool = false
    var alarmType: AlarmType = .none
    var lightsEnabled: Bool = true
    var isArmed: Bool = false
    var isConnected: Bool = false
    var mlcState: MLCState = .unknown
    var silenceEnabled: Bool = false

    // MARK: - Private animation state

    private var timer: Timer?
    private var animationStart: Date = .now
    private var lastState: DisplayState = .off

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        animationStart = .now
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        outputColor = .black
        outputIntensity = 0.0
    }

    // MARK: - State machine

    private enum DisplayState: Equatable {
        case off, findMy, charging, charged, alarmLoud, alarmCalm, stabilizing, locked, rainbow
    }

    private func resolveState() -> DisplayState {
        // Priority 1 — Find My (overrides everything)
        if isFindMyActive { return .findMy }

        // Priority 2 — Cable plugged + actively charging → orange pulse
        if isCablePlugged && isCharging { return .charging }

        // Priority 3 — Cable plugged + full → solid green
        if isCablePlugged && !isCharging { return .charged }

        // Priority 4 — Not connected → off
        if !isConnected { return .off }

        // Priority 5 — Alarm active
        if isAlarmActive {
            guard lightsEnabled && !silenceEnabled else { return .off }
            switch alarmType {
            case .loud:          return .alarmLoud
            case .calm, .normal: return .alarmCalm
            case .none:          return .off
            }
        }

        // Priority 6 — Armed states
        if isArmed {
            // Stabilizing (transitioning to locked)
            if mlcState == .stabilizing {
                return lightsEnabled ? .stabilizing : .off
            }
            // Locked
            return (lightsEnabled && isConnected) ? .locked : .off
        }

        // Priority 7 — Connected idle
        return lightsEnabled ? .rainbow : .off
    }

    // MARK: - Animation tick (~60 fps)

    private func tick() {
        let state = resolveState()

        if state != lastState {
            animationStart = .now
            lastState = state
        }

        let t = Date.now.timeIntervalSince(animationStart)

        switch state {
        case .off:
            outputIntensity = 0.0
            outputColor = .black

        case .findMy:
            // Solid green while Find My tone is active
            outputColor = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
            outputIntensity = 1.0

        case .charging:
            // Orange triangular pulse, 4000 ms full cycle (255, 100, 0)
            outputColor = UIColor(red: 1.0, green: 100.0 / 255.0, blue: 0, alpha: 1)
            outputIntensity = triangleValue(t: t, cycle: 4.0)

        case .charged:
            // Solid green (0, 255, 0)
            outputColor = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
            outputIntensity = 1.0

        case .alarmLoud:
            // Yellow binary flash, 125 ms on/off (255, 225, 0)
            outputColor = UIColor(red: 1.0, green: 225.0 / 255.0, blue: 0, alpha: 1)
            outputIntensity = flashValue(t: t, halfPeriod: 0.125)

        case .alarmCalm:
            // Red binary flash, 300 ms on/off (255, 0, 0)
            outputColor = UIColor(red: 1.0, green: 0, blue: 0, alpha: 1)
            outputIntensity = flashValue(t: t, halfPeriod: 0.300)

        case .stabilizing:
            // Blue triangular pulse, 1000 ms full cycle (0, 0, 255)
            outputColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
            outputIntensity = triangleValue(t: t, cycle: 1.0)

        case .locked:
            // Red triangular pulse, ~1700 ms cycle (step ±3/10 ms)
            outputColor = UIColor(red: 1.0, green: 0, blue: 0, alpha: 1)
            outputIntensity = triangleValue(t: t, cycle: 1.7)

        case .rainbow:
            // 6-phase color wheel, ~1530 ms cycle
            let (r, g, b) = rainbowRGB(t: t)
            outputColor = UIColor(red: r, green: g, blue: b, alpha: 1)
            outputIntensity = 1.0
        }
    }

    // MARK: - Animation helpers

    /// Triangular wave 0 → 1 → 0 over `cycle` seconds (matches firmware linear ramp).
    private func triangleValue(t: Double, cycle: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: cycle)
        let half = cycle / 2.0
        if phase < half {
            return phase / half
        } else {
            return 1.0 - (phase - half) / half
        }
    }

    /// Binary on/off: on for `halfPeriod` seconds, off for `halfPeriod` seconds.
    private func flashValue(t: Double, halfPeriod: Double) -> Double {
        return Int(t / halfPeriod) % 2 == 0 ? 1.0 : 0.0
    }

    /// 6-phase hue wheel: each phase is 51 steps × 5 ms = 255 ms, full cycle ~1530 ms.
    private func rainbowRGB(t: Double) -> (CGFloat, CGFloat, CGFloat) {
        let phaseDuration = 0.255          // 255 ms per phase
        let totalCycle    = 6 * phaseDuration  // ~1530 ms
        let wrapped  = t.truncatingRemainder(dividingBy: totalCycle)
        let phaseIdx = Int(wrapped / phaseDuration) % 6
        let frac     = CGFloat((wrapped - Double(phaseIdx) * phaseDuration) / phaseDuration)

        switch phaseIdx {
        case 0: return (1,     frac,     0    )  // red    → yellow
        case 1: return (1-frac, 1,       0    )  // yellow → green
        case 2: return (0,     1,        frac )  // green  → cyan
        case 3: return (0,     1 - frac, 1    )  // cyan   → blue
        case 4: return (frac,  0,        1    )  // blue   → magenta
        case 5: return (1,     0,        1-frac)  // magenta → red
        default: return (1, 0, 0)
        }
    }
}
