//
//  DeviceNameManager.swift
//  BluetoothTesting
//
//  Created by Assistant on 11/26/24.
//

import Foundation
import Observation

@Observable
class DeviceNameManager {
    static let shared = DeviceNameManager()

    private var customNames: [String: String] = [:] // UUID string -> custom name
    
    private let customNamesKey = "watchdog_custom_device_names"
    
    private init() {
        loadCustomNames()
    }
    
    // MARK: - Custom Name Management
    
    /// Set a custom name for a device UUID
    func setCustomName(deviceID: UUID, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            // Remove custom name if blank - will fall back to advertising name
            removeCustomName(deviceID: deviceID)
        } else {
            customNames[deviceID.uuidString] = trimmedName
            saveCustomNames()
            Log.ok(.name, "Set custom name [\(deviceID.uuidString.prefix(8))] · \(trimmedName)")
        }
    }

    /// Remove custom name for a device UUID
    func removeCustomName(deviceID: UUID) {
        customNames.removeValue(forKey: deviceID.uuidString)
        saveCustomNames()
        Log.ok(.name, "Removed custom name [\(deviceID.uuidString.prefix(8))]")
    }
    
    /// Get custom name for a device UUID (returns nil if no custom name set)
    func getCustomName(deviceID: UUID) -> String? {
        return customNames[deviceID.uuidString]
    }
    
    /// Get display name for a device - custom name if exists, otherwise advertising name
    func getDisplayName(deviceID: UUID, advertisingName: String) -> String {
        return getCustomName(deviceID: deviceID) ?? advertisingName
    }
    
    /// Check if a device has a custom name set
    func hasCustomName(deviceID: UUID) -> Bool {
        return customNames[deviceID.uuidString] != nil
    }
    
    // MARK: - Persistence
    
    private func saveCustomNames() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(customNames)
            UserDefaults.standard.set(data, forKey: customNamesKey)
            Log.info(.persist, "Saved \(customNames.count) custom names")
        } catch {
            Log.err(.persist, "Save custom names · \(error)")
        }
    }

    private func loadCustomNames() {
        guard let data = UserDefaults.standard.data(forKey: customNamesKey) else {
            Log.info(.persist, "No saved custom names")
            return
        }

        do {
            let decoder = JSONDecoder()
            customNames = try decoder.decode([String: String].self, from: data)
            Log.info(.persist, "Loaded \(customNames.count) custom names")
        } catch {
            Log.err(.persist, "Load custom names · \(error)")
            customNames = [:]
        }
    }
}
