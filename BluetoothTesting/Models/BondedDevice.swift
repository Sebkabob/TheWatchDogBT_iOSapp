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
    var isInRange: Bool {
        guard let rssi = currentRSSI else { return false }
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
