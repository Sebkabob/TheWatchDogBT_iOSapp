//
//  BluetoothDevice.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation
import CoreBluetooth

struct BluetoothDevice: Identifiable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    let rssi: Int
    var isConnected: Bool
}
