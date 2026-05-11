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

    /// How close two timestamps must be (in seconds) to be considered the
    /// same firmware-side event re-fetched after a connection drop. Firmware
    /// stores 1-second precision and the wire format truncates fractional
    /// seconds, so duplicates from a re-drain land at identical timestamps
    /// — but allow a small slop window in case the firmware ever moves to
    /// finer resolution and rounds differently.
    private static let dedupWindowSeconds: TimeInterval = 2.0

    func addMotionEvent(_ event: MotionEvent) {
        // Dedup. The firmware's CMD_ACK_EVENT is a no-op (only CMD_CLEAR_LOG
        // prunes its ring), so if iOS drops mid-drain, the same ring slots
        // come back on the next reconnect and the previous design appended
        // them as fresh records. Match on (deviceID, eventType, timestamp
        // ± dedupWindowSeconds). Unknown-time events can't be deduped this
        // way — they're rare and fall through.
        if let ts = event.timestamp {
            let isDuplicate = motionEvents.contains { existing in
                existing.deviceID == event.deviceID &&
                existing.eventType == event.eventType &&
                (existing.timestamp.map { abs($0.timeIntervalSince(ts)) < Self.dedupWindowSeconds } ?? false)
            }
            if isDuplicate {
                Log.warn(.motion, "Duplicate suppressed · \(event.eventType.displayName) at \(ts)")
                return
            }
        }

        let insertIndex = motionEvents.firstIndex { Self.sortsBefore(event, $0) } ?? motionEvents.endIndex
        motionEvents.insert(event, at: insertIndex)
        saveMotionEvents()
        let stampStr = event.timestamp.map { "\($0)" } ?? "unknown time"
        Log.ok(.motion, "Event · \(event.eventType.displayName) at \(stampStr)")
    }

    func clearAllEvents(for deviceID: UUID) {
        motionEvents.removeAll { $0.deviceID == deviceID }
        saveMotionEvents()
        Log.ok(.motion, "Cleared all events [\(deviceID.uuidString.prefix(8))]")
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
