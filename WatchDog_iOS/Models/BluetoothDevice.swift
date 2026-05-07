//
//  BluetoothDevice.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation
import CoreBluetooth

struct BluetoothDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    let rssi: Int
    var isConnected: Bool
    
    // Equatable conformance - compare by ID since peripheral can't be compared
    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.rssi == rhs.rssi &&
               lhs.isConnected == rhs.isConnected
    }
}
