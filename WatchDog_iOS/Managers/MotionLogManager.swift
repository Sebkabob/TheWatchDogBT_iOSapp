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

    /// Tight dedup window: drain-replay protection only. The firmware's
    /// CMD_ACK_EVENT is a no-op (only CMD_CLEAR_LOG prunes its ring), so
    /// if iOS drops mid-drain the same ring slots come back on reconnect.
    /// Same-(deviceID, type, duration) records arriving within 2 s of each
    /// other are treated as the same event and the duplicate is dropped.
    /// Distinct motion events (even of the same type) are NEVER coalesced
    /// — once an event is recorded, its fields are immutable.
    private static let dedupWindowSeconds: TimeInterval = 2.0

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

        // Drain-replay suppression — and ONLY suppression. If a same-
        // (deviceID, type, duration) record already exists within 2 s of
        // the incoming timestamp, drop the new one as a re-drained
        // duplicate. We do NOT compare durations to decide whether to
        // "promote" an existing entry — once written, an entry is
        // immutable.
        //
        // History note: this method used to (a) promote durations in
        // place when a same-(deviceID, type) record arrived with a
        // higher duration than the existing one, and (b) walk back up to
        // 90 s to coalesce an "alarm-fire sentinel" (dur=1) with the
        // matching bout-flush alert (dur=<real>). Both behaviours were
        // designed against an older firmware that emitted two alerts per
        // bout (a sentinel at alarm-fire + a flush at settle). The
        // current firmware sends ONE alert per bout — the wider window
        // started cannibalising legitimate older entries, walking
        // backwards through the log on every new bout and rewriting
        // older entries' durations. Both behaviours are now removed.
        let isDrainReplay = motionEvents.contains { existing in
            existing.deviceID == event.deviceID &&
            existing.eventType == event.eventType &&
            (existing.durationTicks250ms ?? 0) == (event.durationTicks250ms ?? 0) &&
            (existing.timestamp.map { abs($0.timeIntervalSince(ts)) < Self.dedupWindowSeconds } ?? false)
        }
        if isDrainReplay {
            Log.warn(.motion, "Drain-replay duplicate suppressed · \(event.eventType.displayName) at \(ts)")
            return
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
