//
//  MotionLogManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 1/13/26.
//

import Foundation
import Observation

@Observable
class MotionLogManager {
    static let shared = MotionLogManager()

    var motionEvents: [MotionEvent] = []
    
    private let motionEventsKey = "watchdog_motion_events"
    
    private init() {
        loadMotionEvents()
    }
    
    // MARK: - Motion Event Management

    /// Compares two events for descending-by-time order, with `nil` timestamps
    /// floating to the top so the user notices unknown-time events. UUID acts
    /// as the deterministic tiebreaker when timestamps match exactly.
    private static func sortsBefore(_ a: MotionEvent, _ b: MotionEvent) -> Bool {
        switch (a.timestamp, b.timestamp) {
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

    /// Tight dedup: drain-replay protection. The firmware's CMD_ACK_EVENT
    /// is a no-op (only CMD_CLEAR_LOG prunes its ring), so if iOS drops
    /// mid-drain the same ring slots come back on reconnect. Same-type
    /// records within ~2 s of each other are treated as the same event.
    private static let dedupWindowSeconds: TimeInterval = 2.0

    /// Wide alarm-replacement window: covers the gap between the
    /// firmware's initial duration=1 sentinel (sent at alarm-fire so iOS
    /// flips isAlarmActive immediately) and the bout-flush alert
    /// (duration=<real bout>) emitted when motion settles. Worst case is
    /// alarm_duration_seconds_max (30 s) + bout_ticks_max (~64 s); 90 s
    /// safely catches both even back-to-back. Only used when promoting
    /// dur=1 → dur>1 within the window — distinct alarm events with real
    /// durations are NOT collapsed.
    private static let alarmDedupWindowSeconds: TimeInterval = 90.0

    func addMotionEvent(_ event: MotionEvent) {
        // Unknown-time events can't be matched on timestamp — they're rare
        // and fall through to a straight append.
        guard let ts = event.timestamp else {
            let insertIndex = motionEvents.firstIndex { Self.sortsBefore(event, $0) } ?? motionEvents.endIndex
            motionEvents.insert(event, at: insertIndex)
            saveMotionEvents()
            Log.ok(.motion, "Event · \(event.eventType.displayName) at unknown time")
            return
        }

        // Tight dedup first. A re-drained event is a same-(deviceID, type)
        // record within 2 s. If the new record has a higher duration field
        // (firmware can re-send a bout with updated duration when iOS
        // drained mid-bout), promote in place; otherwise suppress as a
        // pure duplicate.
        if let idx = motionEvents.firstIndex(where: { existing in
            existing.deviceID == event.deviceID &&
            existing.eventType == event.eventType &&
            (existing.timestamp.map { abs($0.timeIntervalSince(ts)) < Self.dedupWindowSeconds } ?? false)
        }) {
            let existing = motionEvents[idx]
            let existingDur = existing.durationTicks250ms ?? 0
            let newDur = event.durationTicks250ms ?? 0
            if newDur > existingDur {
                replaceInPlace(at: idx, existing: existing, with: event)
                Log.ok(.motion, "Duplicate replaced (dur \(existingDur) → \(newDur) ticks) · \(event.eventType.displayName)")
            } else {
                Log.warn(.motion, "Duplicate suppressed · \(event.eventType.displayName) at \(ts)")
            }
            return
        }

        // Wide alarm-bout replacement. A single alarm cycle produces two
        // alerts on iOS: an initial duration=1 sentinel (flips
        // isAlarmActive at alarm-fire time) and a duration=<real> bout
        // flush at alarm-exit time. Coalesce them into one record by
        // promoting a same-type, alarm-sounded, dur=1 sentinel within
        // 90 s into the real bout duration. Distinct alarm cycles
        // (existing.dur > 1) are NOT touched here — they remain
        // separate records.
        if event.alarmSounded,
           let newDur = event.durationTicks250ms, newDur > 1 {
            if let idx = motionEvents.firstIndex(where: { existing in
                existing.deviceID == event.deviceID &&
                existing.eventType == event.eventType &&
                existing.alarmSounded &&
                (existing.durationTicks250ms ?? 0) == 1 &&
                (existing.timestamp.map { abs($0.timeIntervalSince(ts)) < Self.alarmDedupWindowSeconds } ?? false)
            }) {
                let existing = motionEvents[idx]
                replaceInPlace(at: idx, existing: existing, with: event)
                Log.ok(.motion, "Alarm sentinel promoted (→ \(newDur) ticks) · \(event.eventType.displayName)")
                return
            }
        }

        let insertIndex = motionEvents.firstIndex { Self.sortsBefore(event, $0) } ?? motionEvents.endIndex
        motionEvents.insert(event, at: insertIndex)
        saveMotionEvents()
        Log.ok(.motion, "Event · \(event.eventType.displayName) at \(ts)")
        // Session-repository rebuild + SessionLocationStore.associate
        // used to run here, but accessing those singletons lazily on the
        // BLE-drain hot path can chain into CLLocationManager init and
        // a full parser pass over hundreds of events — both on the main
        // thread inside a CoreBluetooth callback — which was eating the
        // loyalty-handshake budget and breaking connections. Both pieces
        // of work are now triggered from MotionReportView's onAppear
        // instead: same end result, none of it on the BLE path.
    }

    /// Swap the record at `idx` for a new record that carries the
    /// incoming event's duration but keeps the existing record's id and
    /// timestamp. Preserves session-location / session-name bindings
    /// (keyed on event id) and prevents the row from jumping in the
    /// time-sorted feed when a late bout-flush updates an earlier
    /// alarm-fire sentinel. `alarmSounded` is OR-ed so a true bit from
    /// either side wins.
    private func replaceInPlace(at idx: Int,
                                existing: MotionEvent,
                                with event: MotionEvent) {
        let replacement = MotionEvent(
            id: existing.id,
            deviceID: event.deviceID,
            timestamp: existing.timestamp,
            eventType: event.eventType,
            alarmSounded: event.alarmSounded || existing.alarmSounded,
            durationTicks250ms: event.durationTicks250ms
        )
        motionEvents.remove(at: idx)
        let insertIndex = motionEvents.firstIndex { Self.sortsBefore(replacement, $0) } ?? motionEvents.endIndex
        motionEvents.insert(replacement, at: insertIndex)
        saveMotionEvents()
    }

    func clearAllEvents(for deviceID: UUID, protecting: Set<UUID> = []) {
        motionEvents.removeAll { event in
            if protecting.contains(event.id) { return false }
            return event.deviceID == deviceID
        }
        saveMotionEvents()
        Log.ok(.motion, "Cleared all events [\(deviceID.uuidString.prefix(8))] · protected \(protecting.count)")
    }

    func clearAll() {
        motionEvents.removeAll()
        UserDefaults.standard.removeObject(forKey: motionEventsKey)
        Log.ok(.motion, "Cleared all motion events")
    }

    func clearEventsForDate(_ date: Date, deviceID: UUID) {
        let calendar = Calendar.current
        motionEvents.removeAll { event in
            guard event.deviceID == deviceID, let ts = event.timestamp else { return false }
            return calendar.isDate(ts, inSameDayAs: date)
        }
        saveMotionEvents()
        Log.ok(.motion, "Cleared events for \(date) [\(deviceID.uuidString.prefix(8))]")
    }

    /// Remove every event for `deviceID` whose timestamp falls inside the
    /// half-open range `[start, end)`. Used by the Motion Report screen's
    /// per-day / per-week / per-month "clear" menu options. iOS-local
    /// only — the firmware ring's CMD_CLEAR_LOG is a wipe-all, so we
    /// don't propagate partial-range clears down to the device.
    /// Events with `nil` timestamps are never matched (they have no day).
    /// `protecting` is a set of event IDs that must NEVER be removed —
    /// used to keep the active session's events alive across clears.
    func clearEventsInRange(_ range: Range<Date>, deviceID: UUID, protecting: Set<UUID> = []) {
        motionEvents.removeAll { event in
            guard event.deviceID == deviceID, let ts = event.timestamp else { return false }
            if protecting.contains(event.id) { return false }
            return range.contains(ts)
        }
        saveMotionEvents()
        Log.ok(.motion, "Cleared events in [\(range.lowerBound) … \(range.upperBound)) [\(deviceID.uuidString.prefix(8))] · protected \(protecting.count)")
    }

    /// Remove the events that make up the given sessions — the
    /// SESSION_START marker, every motion event between bookends, and
    /// the SESSION_END marker (when present). Used by the per-session
    /// and per-location delete menus in Motion Report. iOS-local
    /// only; the firmware ring is unaffected.
    func remove(sessions: [MotionSession]) {
        guard !sessions.isEmpty else { return }
        var idsToRemove = Set<UUID>()
        for session in sessions {
            idsToRemove.formUnion(session.allEventIDs)
        }
        let before = motionEvents.count
        motionEvents.removeAll { idsToRemove.contains($0.id) }
        let removed = before - motionEvents.count
        if removed > 0 {
            saveMotionEvents()
            Log.ok(.motion, "Removed \(sessions.count) session(s), \(removed) event(s)")
        }
    }

    // MARK: - Query Methods

    func eventsForDevice(_ deviceID: UUID) -> [MotionEvent] {
        motionEvents.filter { $0.deviceID == deviceID }
    }

    func getEvents(for date: Date, deviceID: UUID) -> [MotionEvent] {
        let calendar = Calendar.current
        return motionEvents.filter { event in
            guard event.deviceID == deviceID, let ts = event.timestamp else { return false }
            return calendar.isDate(ts, inSameDayAs: date)
        }
    }

    /// Events for this device whose firmware-reported timestamp was the
    /// unanchored sentinel — surfaced separately in the UI.
    func unknownTimeEvents(for deviceID: UUID) -> [MotionEvent] {
        motionEvents.filter { $0.deviceID == deviceID && $0.timestamp == nil }
    }

    func getDatesWithEvents(for deviceID: UUID) -> Set<Date> {
        let calendar = Calendar.current
        return Set(eventsForDevice(deviceID).compactMap { event -> Date? in
            guard let ts = event.timestamp else { return nil }
            return calendar.startOfDay(for: ts)
        })
    }
    
    // MARK: - Persistence
    
    private func saveMotionEvents() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(motionEvents)
            UserDefaults.standard.set(data, forKey: motionEventsKey)
            Log.info(.persist, "Saved \(motionEvents.count) motion events")
        } catch {
            Log.err(.persist, "Save motion events · \(error)")
        }
    }

    private func loadMotionEvents() {
        guard let data = UserDefaults.standard.data(forKey: motionEventsKey) else {
            Log.info(.persist, "No saved motion events")
            return
        }

        do {
            let decoder = JSONDecoder()
            motionEvents = try decoder.decode([MotionEvent].self, from: data)
            motionEvents.sort(by: Self.sortsBefore)
            Log.info(.persist, "Loaded \(motionEvents.count) motion events")
        } catch {
            Log.err(.persist, "Load motion events · \(error)")
            motionEvents = []
        }
    }
}
