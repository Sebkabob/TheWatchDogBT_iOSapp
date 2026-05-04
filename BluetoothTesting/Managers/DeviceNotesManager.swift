//
//  DeviceNotesManager.swift
//  BluetoothTesting
//

import Foundation

class DeviceNotesManager {
    static let shared = DeviceNotesManager()

    private let storageKey = "watchdog_device_notes"
    private var notes: [String: String] = [:] // UUID string -> notes

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            notes = decoded
        }
    }

    func getNotes(deviceID: UUID) -> String {
        notes[deviceID.uuidString] ?? ""
    }

    func setNotes(deviceID: UUID, text: String) {
        notes[deviceID.uuidString] = text
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
