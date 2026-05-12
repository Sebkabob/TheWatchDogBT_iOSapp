//
//  MotionSessionParser.swift
//  WatchDog_iOS
//
//  Created by Sebastian Forenza 2026.
//
//  Pure derivation: flat motion-event log → [MotionSession]. No I/O, no
//  storage, no observation — just a function you can unit-test in isolation.
//  The repository owns the live data; the parser doesn't.
//
//  Pairing rules:
//    - SESSION_START opens a session. A second SESSION_START before END
//      orphans the first (status .incomplete) and starts a new one.
//    - SESSION_END closes the most recent open session. An END without a
//      matching START is dropped silently — it can happen on a partial
//      drain or when the logging bit toggles mid-session.
//    - Motion events between START and END are bundled into the session.
//    - Events that arrive without any open session (no preceding START)
//      are ignored at parse time; they're still visible via the raw
//      MotionLogManager if anyone needs them.
//
//  Open-tail handling:
//    The newest SESSION_START with no END is the live session. Its status
//    depends on what the device is doing right now (caller passes
//    `currentlyArmed`) and on the post-disarm grace window. While ARMED
//    is set or we're inside the 5s post-disarm watchdog window, the tail
//    is `.active`. Past that, it's `.incomplete`.
//

import Foundation

struct MotionSessionParser {

    /// Default grace period — should match
    /// MotionSessionsRepository.disarmGracePeriod. Lives here as a default
    /// so unit tests don't have to drag the repository in.
    static let defaultGracePeriod: TimeInterval = 5.0

    /// Parse a flat event list into ordered sessions. Output is sorted
    /// newest-first so the feed renders without an extra sort pass.
    /// - Parameters:
    ///   - events: every MotionEvent across the device's history. Caller
    ///     usually passes MotionLogManager.shared.motionEvents directly.
    ///   - currentlyArmed: live ARMED-bit read from BluetoothManager. Used
    ///     only when classifying the tail session.
    ///   - lastDisarmAt: timestamp of the most recent ARMED 1→0 transition
    ///     observed on iOS. `nil` if no disarm has been seen this session
    ///     of the app.
    ///   - gracePeriod: how long after a disarm we'll still call the tail
    ///     "active" before flipping to "incomplete". Defaults to 5s.
    ///   - now: injection seam for tests.
    static func parse(events: [MotionEvent],
                      currentlyArmed: Bool,
                      isConnected: Bool = true,
                      lastDisarmAt: Date?,
                      gracePeriod: TimeInterval = defaultGracePeriod,
                      now: Date = Date()) -> [MotionSession] {

        let sorted = events.sorted { Self.sortsOldestFirst($0, $1) }

        var sessions: [MotionSession] = []
        var openStart: MotionEvent? = nil
        var openEvents: [MotionEvent] = []

        // Future-stamp cutoff: any non-marker event whose timestamp is
        // implausibly far in the future is treated as corrupt data, not
        // bundled into the open session. This catches polluted historical
        // events that picked up bogus year-2099-style timestamps from old
        // firmware-anchor bugs and would otherwise sort after a current
        // SESSION_START.
        let futureCutoff = now.addingTimeInterval(60)

        for event in sorted {
            switch event.eventType {
            case .sessionStart:
                if let start = openStart {
                    sessions.append(makeSession(start: start,
                                                endEvent: nil,
                                                events: openEvents,
                                                status: .incomplete))
                }
                openStart = event
                openEvents = []

            case .sessionEnd:
                if let start = openStart {
                    sessions.append(makeSession(start: start,
                                                endEvent: event,
                                                events: openEvents,
                                                status: classify(events: openEvents)))
                    openStart = nil
                    openEvents = []
                }

            default:
                guard let openStart else { continue }
                // Timestamp-range filter. Iteration order alone isn't safe:
                // a SESSION_START with a nil timestamp sorts to the front
                // of the chronological list, so every real-timestamped
                // event below would bundle into it. And even with a
                // valid SESSION_START, historical iOS-cached events that
                // landed in the future-stamped past from old firmware
                // anchor bugs would also bundle. We require the event to
                // fall within [start, end-or-now] when timestamps allow it.
                if let startTime = openStart.timestamp,
                   let eventTime = event.timestamp {
                    if eventTime < startTime { continue }
                    if eventTime > futureCutoff { continue }
                } else if openStart.timestamp == nil && event.timestamp != nil {
                    // SESSION_START is unanchored (was logged before iOS
                    // set the firmware clock — e.g., the auto-disarm
                    // race at connect time) but the event has a real
                    // timestamp. Iteration order is the only signal we
                    // have, and it puts the SESSION_START first by sort
                    // even though it really happened later. Refuse to
                    // bundle: the resulting session would be misleading.
                    continue
                }
                openEvents.append(event)
            }
        }

        if let start = openStart {
            // Tail-status rules:
            //   - Disconnected: we can't observe the device's current
            //     state, so the session is `.activeOffline` regardless
            //     of what currentlyArmed reads. (deviceState gets reset
            //     to 0 on disconnect, so currentlyArmed is misleading
            //     here — we'd otherwise wrongly say .incomplete.)
            //   - Connected + armed: live session, `.active`.
            //   - Connected + recently disarmed (within grace window):
            //     still `.active`; SESSION_END is presumably en route.
            //   - Connected + not armed past grace: truly orphaned →
            //     `.incomplete`.
            let tailStatus: SessionStatus
            if !isConnected {
                tailStatus = .activeOffline
            } else if currentlyArmed {
                tailStatus = .active
            } else if let disarm = lastDisarmAt,
                      now.timeIntervalSince(disarm) < gracePeriod {
                tailStatus = .active
            } else {
                tailStatus = .incomplete
            }
            sessions.append(makeSession(start: start,
                                        endEvent: nil,
                                        events: openEvents,
                                        status: tailStatus))
        }

        return sessions.sorted { Self.sortsNewestFirst($0, $1) }
    }

    /// Same chronological ordering rule MotionLogManager uses: nil
    /// timestamps float to the front of the chronological pass so they
    /// fall before everything else, UUID breaks ties deterministically.
    private static func sortsOldestFirst(_ a: MotionEvent, _ b: MotionEvent) -> Bool {
        switch (a.timestamp, b.timestamp) {
        case (nil, nil):
            return a.id.uuidString < b.id.uuidString
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (ta?, tb?):
            if ta == tb { return a.id.uuidString < b.id.uuidString }
            return ta < tb
        }
    }

    private static func sortsNewestFirst(_ a: MotionSession, _ b: MotionSession) -> Bool {
        switch (a.startedAt, b.startedAt) {
        case (nil, nil):
            return a.id.uuidString > b.id.uuidString
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (ta?, tb?):
            if ta == tb { return a.id.uuidString > b.id.uuidString }
            return ta > tb
        }
    }

    /// Empty session → peaceful. Any event with alarmSounded → alarmed.
    /// Anything in between → disturbed.
    private static func classify(events: [MotionEvent]) -> SessionStatus {
        if events.contains(where: { $0.alarmSounded }) { return .alarmed }
        if !events.isEmpty { return .disturbed }
        return .peaceful
    }

    private static func makeSession(start: MotionEvent,
                                    endEvent: MotionEvent?,
                                    events: [MotionEvent],
                                    status: SessionStatus) -> MotionSession {
        MotionSession(id: start.id,
                      deviceID: start.deviceID,
                      startedAt: start.timestamp,
                      endedAt: endEvent?.timestamp,
                      status: status,
                      events: events)
    }
}
