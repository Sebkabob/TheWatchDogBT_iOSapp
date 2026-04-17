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
        case off, findMy, charging, charged, alarmLoud, alarmCalm, locked, rainbow
    }

    private func resolveState() -> DisplayState {
        // Priority 1 — Find My (overrides everything)
        if isFindMyActive { return .findMy }

        // Priority 2 — Cable plugged + actively charging → orange pulse
        if isCablePlugged && isCharging { return .charging }

        // Priority 3 — Cable plugged + fully charged → green pulse
        if isCablePlugged && isBatteryFull { return .charged }

        // Priority 4–6 — Alarm active
        if isAlarmActive {
            guard lightsEnabled else { return .off }
            switch alarmType {
            case .loud:          return .alarmLoud
            case .calm, .normal: return .alarmCalm
            case .none:          return .off
            }
        }

        // Priority 7 — Locked / Armed (no alarm)
        if isArmed {
            guard isConnected && lightsEnabled else { return .off }
            return .locked
        }

        // Priority 8–10 — Connected idle or fully off
        guard isConnected && lightsEnabled else { return .off }
        return .rainbow
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
            // Solid green while Find My is active
            outputColor = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
            outputIntensity = 1.0

        case .charging:
            // Slow orange pulse, 4 000 ms full cycle (255, 100, 0)
            outputColor = UIColor(red: 1.0, green: 100.0 / 255.0, blue: 0, alpha: 1)
            outputIntensity = sineValue(t: t, cycle: 4.0)

        case .charged:
            // Slow green pulse, 4 000 ms full cycle (0, 255, 0)
            outputColor = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
            outputIntensity = sineValue(t: t, cycle: 4.0)

        case .alarmLoud:
            // Amber/yellow binary flash, toggle every 125 ms (255, 225, 0)
            outputColor = UIColor(red: 1.0, green: 225.0 / 255.0, blue: 0, alpha: 1)
            outputIntensity = flashValue(t: t, halfPeriod: 0.125)

        case .alarmCalm:
            // Red binary flash, toggle every 300 ms (255, 0, 0)
            outputColor = UIColor(red: 1.0, green: 0, blue: 0, alpha: 1)
            outputIntensity = flashValue(t: t, halfPeriod: 0.300)

        case .locked:
            // Slow red pulse, ≈ 1 700 ms cycle (step ±3/10 ms)
            outputColor = UIColor(red: 1.0, green: 0, blue: 0, alpha: 1)
            outputIntensity = sineValue(t: t, cycle: 1.7)

        case .rainbow:
            // Smooth hue rotation: red→yellow→green→cyan→blue→magenta, 1 500 ms cycle
            let (r, g, b) = rainbowRGB(t: t)
            outputColor = UIColor(red: r, green: g, blue: b, alpha: 1)
            outputIntensity = 1.0
        }
    }

    // MARK: - Animation helpers

    /// Sine-shaped fade 0 → 1 → 0 over `cycle` seconds, starting at 0.
    private func sineValue(t: Double, cycle: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: cycle)
        return (sin(phase * .pi * 2 / cycle - .pi / 2) + 1) / 2
    }

    /// Binary on/off: on for `halfPeriod` seconds, off for `halfPeriod` seconds.
    private func flashValue(t: Double, halfPeriod: Double) -> Double {
        return Int(t / halfPeriod) % 2 == 0 ? 1.0 : 0.0
    }

    /// 6-phase hue wheel: each phase is 50 steps × 5 ms = 250 ms, full cycle 1 500 ms.
    private func rainbowRGB(t: Double) -> (CGFloat, CGFloat, CGFloat) {
        let phaseDuration = 0.25           // 250 ms per phase
        let totalCycle    = 6 * phaseDuration  // 1 500 ms
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
