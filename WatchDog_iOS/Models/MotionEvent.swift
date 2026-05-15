//
//  MotionEvent.swift
//  BluetoothTesting
//
//  Created by Assistant on 1/6/26.
//

import Foundation

enum MotionEventType: UInt8, Codable {
    case none         = 0
    case inMotion     = 1
    case shaken       = 2
    case impact       = 3
    case freefall     = 4
    case tilted       = 5
    case doorOpening  = 6
    case doorClosing  = 7
    /// Firmware-emitted SESSION_START marker (motion-logger value 0x10).
    /// Not a "motion" event per se — bookends a locked period for the
    /// MotionSessionParser. Display strings are mostly never seen in
    /// regular UI because the parser pulls these out of the events array
    /// before rendering; they appear only in the Session detail screen's
    /// event log as "Session start · locked".
    case sessionStart = 0x10
    /// Firmware-emitted SESSION_END marker (motion-logger value 0x11).
    case sessionEnd   = 0x11

    var displayName: String {
        switch self {
        case .none:         return "None"
        case .inMotion:     return "In Motion"
        case .shaken:       return "Shaken"
        case .impact:       return "Impact"
        case .freefall:     return "Free Fall"
        case .tilted:       return "Tilted"
        case .doorOpening:  return "Door Opening"
        case .doorClosing:  return "Door Closing"
        case .sessionStart: return "Session Start"
        case .sessionEnd:   return "Session End"
        }
    }

    var icon: String {
        switch self {
        case .none:         return "minus.circle"
        case .inMotion:     return "figure.walk"
        case .shaken:       return "waveform.path"
        case .impact:       return "exclamationmark.triangle"
        case .freefall:     return "arrow.down.circle"
        case .tilted:       return "angle"
        case .doorOpening:  return "door.left.hand.open"
        case .doorClosing:  return "door.left.hand.closed"
        case .sessionStart: return "lock.fill"
        case .sessionEnd:   return "lock.open.fill"
        }
    }

    /// True for the firmware session-boundary markers (0x10, 0x11). The
    /// MotionSessionParser treats these as control events and excludes
    /// them from a session's `events` array.
    var isSessionMarker: Bool {
        self == .sessionStart || self == .sessionEnd
    }
}

struct MotionEvent: Identifiable, Codable {
    let id: UUID
    let deviceID: UUID
    /// `nil` when the firmware reported the unanchored sentinel — i.e. it
    /// had no idea what wall-clock time the event occurred at. We deliberately
    /// don't substitute `Date()` here; downstream UI surfaces "Unknown time".
    let timestamp: Date?
    let eventType: MotionEventType
    let alarmSounded: Bool
    /// How long the underlying motion lasted, in 250 ms ticks (firmware
    /// field width — 1..255 → 0.25..63.75 s). `nil` only for legacy
    /// records persisted before the duration field shipped; the parser
    /// surfaces those as "—" and downstream views skip the duration
    /// column. Instantaneous events (FSM impact/freefall, MLC blips
    /// that never reached the deferred-settle path) always carry 1.
    let durationTicks250ms: UInt8?

    /// Convenience: duration as a TimeInterval (seconds). `nil` propagates
    /// the legacy/unknown case from `durationTicks250ms`.
    var durationSeconds: TimeInterval? {
        guard let ticks = durationTicks250ms else { return nil }
        return Double(ticks) * 0.25
    }

    init(id: UUID = UUID(),
         deviceID: UUID,
         timestamp: Date?,
         eventType: MotionEventType,
         alarmSounded: Bool,
         durationTicks250ms: UInt8? = nil) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.eventType = eventType
        self.alarmSounded = alarmSounded
        self.durationTicks250ms = durationTicks250ms
    }
}
