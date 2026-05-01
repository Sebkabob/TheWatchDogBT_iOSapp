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
        motionEvents.append(event)
        motionEvents.sort { $0.timestamp > $1.timestamp }  // Most recent first
        saveMotionEvents()
        print("✅ Added motion event: \(event.eventType.displayName) at \(event.timestamp)")
    }
    
    func addMotionEvents(_ events: [MotionEvent]) {
        motionEvents.append(contentsOf: events)
        motionEvents.sort { $0.timestamp > $1.timestamp }
        saveMotionEvents()
        print("✅ Added \(events.count) motion events")
    }
    
    func clearAllEvents(for deviceID: UUID) {
        motionEvents.removeAll { $0.deviceID == deviceID }
        saveMotionEvents()
        print("🗑️ Cleared all motion events for device \(deviceID.uuidString.prefix(8))")
    }

    func clearEventsForDate(_ date: Date, deviceID: UUID) {
        let calendar = Calendar.current
        motionEvents.removeAll { event in
            event.deviceID == deviceID && calendar.isDate(event.timestamp, inSameDayAs: date)
        }
        saveMotionEvents()
        print("🗑️ Cleared events for \(date) on device \(deviceID.uuidString.prefix(8))")
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

    func getEventCount(for date: Date, deviceID: UUID) -> Int {
        return getEvents(for: date, deviceID: deviceID).count
    }

    func getMostRecentEventDate(for deviceID: UUID) -> Date? {
        return eventsForDevice(deviceID).first?.timestamp
    }

    func getDatesWithEvents(for deviceID: UUID) -> Set<Date> {
        let calendar = Calendar.current
        return Set(eventsForDevice(deviceID).map { event in
            calendar.startOfDay(for: event.timestamp)
        })
    }
    
    // MARK: - Sync with WatchDog
    
    /// Process incoming motion event data from WatchDog
    func processIncomingEvents(data: Data, deviceID: UUID) {
        guard data.count % 10 == 0 else {
            print("❌ Invalid motion events data length: \(data.count)")
            return
        }

        let eventCount = data.count / 10
        var newEvents: [MotionEvent] = []

        for i in 0..<eventCount {
            let startIndex = i * 10
            let endIndex = startIndex + 10
            let eventData = data[startIndex..<endIndex]

            if let event = MotionEvent.decode(from: Data(eventData), deviceID: deviceID) {
                newEvents.append(event)
            }
        }

        if !newEvents.isEmpty {
            addMotionEvents(newEvents)
            print("📥 Synced \(newEvents.count) motion events from WatchDog")
        }
    }
    
    // MARK: - Persistence
    
    private func saveMotionEvents() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(motionEvents)
            UserDefaults.standard.set(data, forKey: motionEventsKey)
            print("💾 Saved \(motionEvents.count) motion events")
        } catch {
            print("❌ Failed to save motion events: \(error)")
        }
    }
    
    private func loadMotionEvents() {
        guard let data = UserDefaults.standard.data(forKey: motionEventsKey) else {
            print("📭 No saved motion events found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            motionEvents = try decoder.decode([MotionEvent].self, from: data)
            motionEvents.sort { $0.timestamp > $1.timestamp }
            print("📬 Loaded \(motionEvents.count) motion events")
        } catch {
            print("❌ Failed to load motion events: \(error)")
            motionEvents = []
        }
    }
}
