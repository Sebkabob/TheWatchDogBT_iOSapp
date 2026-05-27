//
//  MotionSessionsRepository.swift
//  WatchDog_iOS
//
//  Created by Sebastian Forenza 2026.
//
//  Single source of truth for the derived [MotionSession] list. Observes
//  the raw MotionEvent log (via explicit rebuild() calls from MotionLogManager
//  on add / clear) and tracks the post-disarm watchdog state.
//
//  Watchdog contract:
//    When iOS observes the BluetoothManager's deviceState ARMED bit
//    transition from 1 → 0, BluetoothManager calls noteDisarmObserved().
//    That stamps `lastDisarmAt = now` and arms a 5s timer. While the timer
//    is alive, the parser still calls the open session `.active`. When it
//    fires, we rebuild — if SESSION_END arrived in the interim the session
//    is now closed cleanly; if not, the parser flips the tail to
//    `.incomplete`.
//
//  All published mutations land on the main thread so SwiftUI observation
//  is well-behaved. The repository itself is a singleton because the
//  whole app shares one MotionLogManager and one BluetoothManager.
//

import Foundation
import Observation

@Observable
class MotionSessionsRepository {
    static let shared = MotionSessionsRepository()

    /// Newest-first list of sessions derived from MotionLogManager. Drives
    /// MotionReportView's feed and detail screens.
    var sessions: [MotionSession] = []

    /// Stamp of the most recent ARMED 1→0 observation. Read by the parser
    /// (via rebuild) to decide whether the tail session is still in its
    /// post-disarm grace window. Cleared back to nil when the grace window
    /// expires AND a SESSION_END has been observed for the open session.
    private(set) var lastDisarmAt: Date? = nil

    /// Live armed-bit cache. BluetoothManager pushes this in via
    /// noteArmedStateChange so the parser can render the tail session as
    /// `.active` while the user is still locked.
    private(set) var currentlyArmed: Bool = false

    /// Cached: how long to keep the open session as `.active` after a
    /// disarm before declaring it `.incomplete`. Matches the firmware-
    /// side latency budget — see CLAUDE.md "5-second contract".
    let disarmGracePeriod: TimeInterval = 5.0

    private var disarmTimer: Timer?

    private init() {
        rebuild()
    }

    // MARK: - Update entry points

    /// Re-derive sessions from the current MotionLogManager state. Cheap;
    /// pure function over an array that's bounded at ~169 events on the
    /// device side. Called: on every motion-log mutation, on every
    /// ARMED-bit transition, on watchdog expiry.
    func rebuild() {
        let computed = MotionSessionParser.parse(
            events: MotionLogManager.shared.motionEvents,
            currentlyArmed: currentlyArmed,
            lastDisarmAt: lastDisarmAt,
            gracePeriod: disarmGracePeriod
        )

        if Thread.isMainThread {
            sessions = computed
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.sessions = computed
            }
        }
    }

    /// Called by BluetoothManager whenever it observes the deviceState
    /// ARMED bit change. Tracks both directions:
    ///   - 1 → 0: stamp lastDisarmAt, start the 5s watchdog
    ///   - 0 → 1: clear stale disarm state (a new session is opening)
    func noteArmedStateChange(armed: Bool) {
        let work = { [weak self] in
            guard let self = self else { return }
            let wasArmed = self.currentlyArmed
            self.currentlyArmed = armed

            if wasArmed && !armed {
                self.lastDisarmAt = Date()
                self.disarmTimer?.invalidate()
                self.disarmTimer = Timer.scheduledTimer(
                    withTimeInterval: self.disarmGracePeriod,
                    repeats: false
                ) { [weak self] _ in
                    guard let self = self else { return }
                    self.disarmTimer = nil
                    // Don't clear lastDisarmAt: the parser uses it on
                    // every rebuild. Clearing here would re-arm the
                    // grace window on the next rebuild and we'd never
                    // settle into `.incomplete`. The stamp ages out
                    // naturally relative to now.
                    self.rebuild()
                }
            } else if !wasArmed && armed {
                // New session is being opened. Burn any stale disarm
                // bookkeeping so a previous incomplete-session label
                // doesn't bleed onto the new one.
                self.lastDisarmAt = nil
                self.disarmTimer?.invalidate()
                self.disarmTimer = nil
            }

            self.rebuild()
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Wipe local session derivation alongside MotionLogManager.clear*().
    /// Sessions are pure derivations of events, so once the events are gone
    /// the sessions follow on the next rebuild — but we expose this
    /// helper so callers don't have to know that.
    func clearAll() {
        if Thread.isMainThread {
            sessions = []
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.sessions = []
            }
        }
    }

    // MARK: - Convenience queries

    /// Filter helper for the calendar tab. Returns sessions whose
    /// startedAt falls on the given local day, sorted oldest → newest
    /// so the day view reads top-to-bottom in chronological order.
    func sessions(on day: Date, deviceID: UUID? = nil) -> [MotionSession] {
        let cal = Calendar.current
        return sessions.filter { session in
            if let deviceID, session.deviceID != deviceID { return false }
            guard let start = session.startedAt else { return false }
            return cal.isDate(start, inSameDayAs: day)
        }
        .sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    /// Sessions for a single device, newest-first. Used by the feed tab.
    func sessions(for deviceID: UUID) -> [MotionSession] {
        sessions.filter { $0.deviceID == deviceID }
    }

    /// True iff at least one session for `deviceID` has no SESSION_END
    /// recorded yet. Used by BluetoothManager to decide whether to
    /// synthesise a fresh SESSION_START when reconnecting to a device
    /// that booted back into LOCKED state on its own (firmware ARMED-bit
    /// persistence). If a session is still open, we want to extend it,
    /// not double-up.
    func hasOpenSession(for deviceID: UUID) -> Bool {
        sessions.contains { $0.deviceID == deviceID && $0.endedAt == nil }
    }
}
