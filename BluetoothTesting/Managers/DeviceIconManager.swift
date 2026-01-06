//
//  DeviceIconManager.swift
//  BluetoothTesting
//
//  Created by Assistant on 11/26/24.
//

import Foundation

enum DeviceIcon: String, Codable, CaseIterable {
    case dog = "dog"
    case lockShield = "lock.shield"
    case door = "door.left.hand.closed"
    case bicycle = "bicycle"
    case cabinet = "cabinet"
    case backpack = "backpack"
    case key = "key"
    case bag = "bag"
    case box = "shippingbox"
    case car = "car"
    case house = "house"
    case briefcase = "briefcase"
    case skateboard = "skateboard"
    case motorcycle = "motorcycle"
    case scooter = "scooter"
    case pill = "pill"
    case suitcase = "suitcase.rolling"
    
    var displayName: String {
        switch self {
        case .dog: return "Dog"
        case .lockShield: return "Lock"
        case .door: return "Door"
        case .bicycle: return "Bike"
        case .cabinet: return "Cabinet"
        case .backpack: return "Backpack"
        case .key: return "Keys"
        case .bag: return "Bag"
        case .box: return "Box"
        case .car: return "Car"
        case .house: return "House"
        case .briefcase: return "Briefcase"
        case .skateboard: return "Board"
        case .motorcycle: return "Motorcycle"
        case .scooter: return "Scooter"
        case .pill: return "Pills"
        case .suitcase: return "Luggage"
        }
    }
    
    // Track which icons have .fill variants
    var hasFillVariant: Bool {
        switch self {
        case .dog: return true
        case .lockShield: return true
        case .door: return true
        case .bicycle: return false
        case .cabinet: return true
        case .backpack: return true
        case .key: return true
        case .bag: return true
        case .box: return true
        case .car: return true
        case .house: return true
        case .briefcase: return true
        case .skateboard: return false
        case .motorcycle: return false
        case .scooter: return false
        case .pill: return true
        case .suitcase: return true
        }
    }
}

class DeviceIconManager: ObservableObject {
    static let shared = DeviceIconManager()
    
    @Published private var customIcons: [String: String] = [:] // UUID string -> icon rawValue
    
    private let customIconsKey = "watchdog_custom_device_icons"
    
    private init() {
        loadCustomIcons()
    }
    
    // MARK: - Custom Icon Management
    
    /// Set a custom icon for a device UUID
    func setCustomIcon(deviceID: UUID, icon: DeviceIcon) {
        customIcons[deviceID.uuidString] = icon.rawValue
        saveCustomIcons()
        print("🎨 Set custom icon for \(deviceID.uuidString.prefix(8)): \(icon.displayName)")
    }
    
    /// Remove custom icon for a device UUID (will use default lock.shield)
    func removeCustomIcon(deviceID: UUID) {
        customIcons.removeValue(forKey: deviceID.uuidString)
        saveCustomIcons()
        print("🗑️ Removed custom icon for \(deviceID.uuidString.prefix(8))")
    }
    
    /// Get custom icon for a device UUID (returns nil if no custom icon set)
    func getCustomIcon(deviceID: UUID) -> DeviceIcon? {
        guard let iconString = customIcons[deviceID.uuidString],
              let icon = DeviceIcon(rawValue: iconString) else {
            return nil
        }
        return icon
    }
    
    /// Get display icon for a device - custom icon if exists, otherwise default lock.shield
    func getDisplayIcon(deviceID: UUID) -> DeviceIcon {
        return getCustomIcon(deviceID: deviceID) ?? .lockShield
    }
    
    /// Check if a device has a custom icon set
    func hasCustomIcon(deviceID: UUID) -> Bool {
        return customIcons[deviceID.uuidString] != nil
    }
    
    // MARK: - Persistence
    
    private func saveCustomIcons() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(customIcons)
            UserDefaults.standard.set(data, forKey: customIconsKey)
            print("💾 Saved \(customIcons.count) custom icons")
        } catch {
            print("❌ Failed to save custom icons: \(error)")
        }
    }
    
    private func loadCustomIcons() {
        guard let data = UserDefaults.standard.data(forKey: customIconsKey) else {
            print("📭 No saved custom icons found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            customIcons = try decoder.decode([String: String].self, from: data)
            print("📬 Loaded \(customIcons.count) custom icons")
        } catch {
            print("❌ Failed to load custom icons: \(error)")
            customIcons = [:]
        }
    }
}
