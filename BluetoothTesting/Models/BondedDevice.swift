//
//  BondedDevice.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 11/23/24.
//

import Foundation
import CoreBluetooth

struct BondedDevice: Identifiable, Codable {
    let id: UUID
    var name: String
    var dateAdded: Date
    var lastSeen: Date?
    
    // Runtime properties (not stored)
    var currentRSSI: Int?
    
    // Check if device is in range based on RSSI and last seen time
    var isInRange: Bool {
        guard let rssi = currentRSSI, let lastSeenTime = lastSeen else { return false }
        
        // Device is out of range if we haven't seen it in 3 seconds
        let timeSinceLastSeen = Date().timeIntervalSince(lastSeenTime)
        guard timeSinceLastSeen <= 3.0 else { return false }
        
        // Also check RSSI threshold
        return rssi > -95
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, dateAdded, lastSeen
    }
    
    init(id: UUID, name: String, dateAdded: Date = Date()) {
        self.id = id
        self.name = name
        self.dateAdded = dateAdded
        self.lastSeen = nil
        self.currentRSSI = nil
    }
}
