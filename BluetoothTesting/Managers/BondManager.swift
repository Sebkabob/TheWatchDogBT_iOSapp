//
//  BondManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 11/23/24.
//

import Foundation
import CoreBluetooth

class BondManager: ObservableObject {
    static let shared = BondManager()
    
    @Published var bondedDevices: [BondedDevice] = []
    
    private let bondsKey = "watchdog_bonded_devices"
    
    private init() {
        loadBonds()
    }
    
    // MARK: - Bond Management
    
    func addBond(deviceID: UUID, name: String) {
        // Check if already bonded
        if bondedDevices.contains(where: { $0.id == deviceID }) {
            print("⚠️ Device already bonded: \(name)")
            return
        }
        
        let newBond = BondedDevice(id: deviceID, name: name)
        bondedDevices.append(newBond)
        saveBonds()
        print("✅ Added bond: \(name) [\(deviceID.uuidString.prefix(8))]")
    }
    
    func removeBond(deviceID: UUID) {
        if let index = bondedDevices.firstIndex(where: { $0.id == deviceID }) {
            let name = bondedDevices[index].name
            bondedDevices.remove(at: index)
            saveBonds()
            print("🗑️ Removed bond: \(name) [\(deviceID.uuidString.prefix(8))]")
        }
    }
    
    func updateDeviceRSSI(deviceID: UUID, rssi: Int) {
        if let index = bondedDevices.firstIndex(where: { $0.id == deviceID }) {
            bondedDevices[index].currentRSSI = rssi
            bondedDevices[index].lastSeen = Date()
        }
    }
    
    func updateDeviceName(deviceID: UUID, name: String) {
        if let index = bondedDevices.firstIndex(where: { $0.id == deviceID }) {
            // Only update if the name has changed
            if bondedDevices[index].name != name {
                bondedDevices[index].name = name
                saveBonds()
                print("✏️ Updated device name to: \(name)")
            }
        }
    }
    
    func clearRSSI(deviceID: UUID) {
        if let index = bondedDevices.firstIndex(where: { $0.id == deviceID }) {
            bondedDevices[index].currentRSSI = nil
        }
    }
    
    func clearAllRSSI() {
        for index in bondedDevices.indices {
            bondedDevices[index].currentRSSI = nil
        }
    }
    
    func isBonded(deviceID: UUID) -> Bool {
        return bondedDevices.contains(where: { $0.id == deviceID })
    }
    
    func getBond(deviceID: UUID) -> BondedDevice? {
        return bondedDevices.first(where: { $0.id == deviceID })
    }
    
    func renameBond(deviceID: UUID, newName: String) {
        if let index = bondedDevices.firstIndex(where: { $0.id == deviceID }) {
            bondedDevices[index].name = newName
            saveBonds()
            print("✏️ Renamed device to: \(newName)")
        }
    }
    
    // MARK: - Persistence
    
    private func saveBonds() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(bondedDevices)
            UserDefaults.standard.set(data, forKey: bondsKey)
            print("💾 Saved \(bondedDevices.count) bonds")
        } catch {
            print("❌ Failed to save bonds: \(error)")
        }
    }
    
    private func loadBonds() {
        guard let data = UserDefaults.standard.data(forKey: bondsKey) else {
            print("📭 No saved bonds found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            bondedDevices = try decoder.decode([BondedDevice].self, from: data)
            print("📬 Loaded \(bondedDevices.count) bonds")
        } catch {
            print("❌ Failed to load bonds: \(error)")
            bondedDevices = []
        }
    }
}
