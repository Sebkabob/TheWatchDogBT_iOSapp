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
    
    func addMotionEvent(_ event: MotionEvent) {
        let insertIndex = motionEvents.firstIndex { $0.timestamp <= event.timestamp } ?? motionEvents.endIndex
        motionEvents.insert(event, at: insertIndex)
        saveMotionEvents()
        Log.ok(.motion, "Event · \(event.eventType.displayName) at \(event.timestamp)")
    }

    func clearAllEvents(for deviceID: UUID) {
        motionEvents.removeAll { $0.deviceID == deviceID }
        saveMotionEvents()
        Log.ok(.motion, "Cleared all events [\(deviceID.uuidString.prefix(8))]")
    }

    func clearEventsForDate(_ date: Date, deviceID: UUID) {
        let calendar = Calendar.current
        motionEvents.removeAll { event in
            event.deviceID == deviceID && calendar.isDate(event.timestamp, inSameDayAs: date)
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
            event.deviceID == deviceID && calendar.isDate(event.timestamp, inSameDayAs: date)
        }
    }

    func getDatesWithEvents(for deviceID: UUID) -> Set<Date> {
        let calendar = Calendar.current
        return Set(eventsForDevice(deviceID).map { event in
            calendar.startOfDay(for: event.timestamp)
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
            motionEvents.sort { $0.timestamp > $1.timestamp }
            Log.info(.persist, "Loaded \(motionEvents.count) motion events")
        } catch {
            Log.err(.persist, "Load motion events · \(error)")
            motionEvents = []
        }
    }
}
