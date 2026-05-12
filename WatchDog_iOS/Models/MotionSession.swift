//
//  MotionSession.swift
//  WatchDog_iOS
//
//  Created by Sebastian Forenza 2026.
//
//  A MotionSession is a bookended period of "armed intent" — the device
//  was locked, motion was being watched, then the user unlocked. Sessions
//  are derived from the flat MotionEvent log by MotionSessionParser, which
//  pairs firmware-emitted SESSION_START / SESSION_END markers (motion types
//  0x10 and 0x11) and groups the motion events that fell between them.
//
//  A session has one of five status verdicts, computed once at parse time:
//    .active     — open session (SESSION_START with no END yet) and the
//                  device is still armed. The card pulses, the duration
//                  ticks live.
//    .peaceful   — closed session, no motion events fired. The 90% case.
//    .disturbed  — closed session, motion events fired but no alarm.
//    .alarmed    — closed session, alarm went off mid-session.
//    .incomplete — open session whose end marker never arrived (firmware
//                  reset mid-session, BLE drop right after disarm, etc.).
//                  Triggered by the 5-second post-disarm watchdog in
//                  MotionSessionsRepository.
//

import Foundation
import SwiftUI

enum SessionStatus: String, Codable {
    case active
    /// Session was open at the last known connection but iOS is no
    /// longer connected to the device, so we genuinely don't know its
    /// current state — it might still be armed and protecting, or it
    /// might have been disarmed by an event we can't see. Distinct
    /// from `.incomplete` (which is reserved for sessions where we
    /// know the device is no longer armed but no SESSION_END landed).
    case activeOffline
    case peaceful
    case disturbed
    case alarmed
    case incomplete

    var label: String {
        switch self {
        case .active:         return "Active"
        case .activeOffline:  return "Offline"
        case .peaceful:       return "Peaceful"
        case .disturbed:      return "Disturbed"
        case .alarmed:        return "Alarmed"
        case .incomplete:     return "Incomplete"
        }
    }

    /// Foreground/background pair for the status badge. Maps directly onto
    /// SwiftUI semantic colors so it adapts to light/dark mode without us
    /// hand-rolling palettes.
    var badgeForeground: Color {
        switch self {
        case .active:         return .blue
        case .activeOffline:  return .gray
        case .peaceful:       return .green
        case .disturbed:      return .orange
        case .alarmed:        return .red
        case .incomplete:     return .orange
        }
    }

    var badgeBackground: Color {
        badgeForeground.opacity(0.15)
    }

    /// Used for sparkline / timeline stroke colors so the visual matches
    /// the verdict at a glance.
    var accentColor: Color { badgeForeground }
}

struct MotionSession: Identifiable {
    /// The id of the SESSION_START MotionEvent — stable across rebuilds so
    /// SwiftUI ForEach diffing doesn't churn the rows.
    let id: UUID
    /// id of the SESSION_END MotionEvent if the session was closed
    /// cleanly. Used by delete actions to wipe the matching boundary
    /// marker alongside the SESSION_START. nil for open or orphaned
    /// sessions.
    let endEventID: UUID?
    let deviceID: UUID
    /// Calendar time the session was opened. `nil` if the SESSION_START
    /// landed before iOS anchored the firmware clock — the parser will
    /// surface this as "Unknown start" in the card.
    let startedAt: Date?
    /// Calendar time the session was closed. `nil` for active/incomplete.
    let endedAt: Date?
    let status: SessionStatus
    /// Motion events that fell between SESSION_START and SESSION_END,
    /// sorted oldest → newest. Excludes the boundary markers themselves —
    /// those live as startedAt / endedAt. The detail screen's timeline
    /// chart and event log are both driven by this array.
    let events: [MotionEvent]

    /// Every MotionEvent id that belongs to this session: the SESSION_START,
    /// every motion event between bookends, and the SESSION_END (when the
    /// session was closed). Used by the delete-session menus to remove the
    /// whole record from MotionLogManager in one pass.
    var allEventIDs: Set<UUID> {
        var ids: Set<UUID> = [id]
        ids.formUnion(events.map { $0.id })
        if let endEventID { ids.insert(endEventID) }
        return ids
    }

    /// First moment the alarm sounded during this session, if any. Used by
    /// the detail-screen banner to surface the headline time.
    var alarmFiredAt: Date? {
        events.first(where: { $0.alarmSounded })?.timestamp ?? nil
    }

    /// Wall-clock duration. `nil` when either boundary is missing or when
    /// the session is still active (caller can compute live duration from
    /// startedAt → Date()).
    var duration: TimeInterval? {
        guard let start = startedAt, let end = endedAt else { return nil }
        return end.timeIntervalSince(start)
    }

    /// "2h 14m" / "47s" — short form for badges and card subtitles.
    /// Returns nil-as-"??" for active/incomplete sessions so the UI
    /// doesn't have to special-case rendering.
    func shortDurationString(now: Date = Date()) -> String {
        let interval: TimeInterval
        if let d = duration {
            interval = d
        } else if status == .active, let start = startedAt {
            interval = now.timeIntervalSince(start)
        } else {
            return "??"
        }
        return MotionSession.formatShortDuration(interval)
    }

    static func formatShortDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes.zeroPadded)m" }
        if minutes > 0 { return "\(minutes)m \(seconds.zeroPadded)s" }
        return "\(seconds)s"
    }
}

private extension Int {
    var zeroPadded: String { self < 10 ? "0\(self)" : "\(self)" }
}
