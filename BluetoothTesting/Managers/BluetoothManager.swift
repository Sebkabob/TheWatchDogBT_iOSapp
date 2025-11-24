//
//  BluetoothManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject {
    @Published var discoveredDevices: [BluetoothDevice] = []
    @Published var isScanning = false
    @Published var isBluetoothReady = false
    @Published var connectedDevice: BluetoothDevice?
    @Published var lastSentData: String = ""
    @Published var deviceState: UInt8 = 0
    @Published var hasReceivedInitialState = false
    @Published var batteryLevel: Int = -1
    @Published var isCharging: Bool = false
    
    private let settingsManager = SettingsManager.shared
    
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private let targetServiceUUID = CBUUID(string: "183E")
    
    private var lastRSSIUpdate: [UUID: Date] = [:]
    private let rssiUpdateInterval: TimeInterval = 1.0
    
    private let deviceTimeout: TimeInterval = 5.0
    private var staleDeviceTimer: Timer?
    
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 10.0
    
    var deviceStateText: String {
        // Extract the armed bit (bit 0) from the settings byte
        let isArmed = (deviceState & 0x01) != 0
        
        if isArmed {
            return "Locked"
        } else {
            return "Unlocked"
        }
        
        // You can add alarm detection logic later if needed
        // For now, just check the armed bit
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard isBluetoothReady else { return }
        discoveredDevices.removeAll()
        lastRSSIUpdate.removeAll()
        
        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        print("Started scanning for 0x183E devices")
        
        staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.removeStaleDevices()
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        staleDeviceTimer?.invalidate()
        staleDeviceTimer = nil
    }
    
    func connect(to device: BluetoothDevice) {
        print("Connecting to: \(device.name)")
        centralManager.connect(device.peripheral, options: nil)
        
        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeout, repeats: false) { [weak self] _ in
            print("⏱️ Connection timeout for \(device.name)")
            self?.centralManager.cancelPeripheralConnection(device.peripheral)
            self?.connectionTimer = nil
        }
    }
    
    func disconnect(from device: BluetoothDevice) {
        centralManager.cancelPeripheralConnection(device.peripheral)
        connectedDevice = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        lastSentData = ""
        deviceState = 0
        hasReceivedInitialState = false
        batteryLevel = -1
        isCharging = false
    }
    
    func sendData(_ data: Data) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedDevice?.peripheral else {
            print("No writable characteristic found")
            return
        }
        
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        lastSentData = "0x\(hexString) (\(data.count) bytes)"
        print("Sent: \(lastSentData)")
    }
    
    func sendSettings() {
        let settingsByte = settingsManager.encodeSettings()
        let data = Data([settingsByte])
        sendData(data)
        print("📤 Sent settings byte: 0x\(String(format: "%02X", settingsByte))")
    }
    
    private func removeStaleDevices() {
        let now = Date()
        discoveredDevices.removeAll { device in
            guard let lastUpdate = lastRSSIUpdate[device.id] else {
                return true
            }
            let isStale = now.timeIntervalSince(lastUpdate) > deviceTimeout
            if isStale {
                print("🗑️ Removing stale device: \(device.name)")
                lastRSSIUpdate.removeValue(forKey: device.id)
            }
            return isStale
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothReady = central.state == .poweredOn
        if !isBluetoothReady {
            stopScanning()
            connectedDevice = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceID = peripheral.identifier
        let now = Date()
        
        if let lastUpdate = lastRSSIUpdate[deviceID] {
            if now.timeIntervalSince(lastUpdate) < rssiUpdateInterval {
                return
            }
        }
        
        lastRSSIUpdate[deviceID] = now
        
        // Get name from advertisement data (TOP PRIORITY), fallback to peripheral name
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "WatchDog"
        
        let device = BluetoothDevice(
            id: deviceID,
            name: name,
            peripheral: peripheral,
            rssi: RSSI.intValue,
            isConnected: false
        )
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
            print("Discovered: \(name) [\(deviceID.uuidString.prefix(8))]")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to: \(peripheral.name ?? "Unknown")")
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            // Keep the discovered name, just update connection status
            discoveredDevices[index] = BluetoothDevice(
                id: peripheral.identifier,
                name: discoveredDevices[index].name,  // PRESERVE THE DISCOVERED NAME
                peripheral: peripheral,
                rssi: discoveredDevices[index].rssi,
                isConnected: true
            )
            connectedDevice = discoveredDevices[index]
        }
        
        stopScanning()
        
        peripheral.delegate = self
        peripheral.discoverServices([targetServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from: \(peripheral.name ?? "Unknown")")
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].isConnected = false
        }
        
        connectedDevice = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        lastSentData = ""
        deviceState = 0
        hasReceivedInitialState = false
        batteryLevel = -1
        isCharging = false
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        
        connectionTimer?.invalidate()
        connectionTimer = nil
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("Found characteristic: \(characteristic.uuid)")
            print("  Properties: \(characteristic.properties)")
            
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                print("  ✅ This is writable! Ready to send data.")
            }
            
            if characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("  ✅ Subscribed to notifications!")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error reading characteristic: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else { return }
        
        // Debug: print all received bytes
        print("📦 Received \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // We expect 2 bytes: [settings, battery]
        if data.count >= 1 {
            let settingsByte = data[0]
            
            DispatchQueue.main.async {
                let oldState = self.deviceState
                self.deviceState = settingsByte
                self.hasReceivedInitialState = true
                
                // Decode settings from WatchDog (WatchDog is source of truth!)
                self.settingsManager.decodeSettings(from: settingsByte)
                
                print("📥 Received device state: 0x\(String(format: "%02X", settingsByte)) - \(self.deviceStateText) (was: 0x\(String(format: "%02X", oldState)))")
            }
        }
        
        // Read battery level if available (byte 1)
        if data.count >= 2 {
            let batteryByte = data[1]
            
            // Check bit 7 for charging state (0b10000000 = 0x80)
            let charging = (batteryByte & 0x80) != 0
            
            // Extract actual battery level from lower 7 bits
            let battery = Int(batteryByte & 0x7F)
            
            DispatchQueue.main.async {
                self.batteryLevel = battery
                self.isCharging = charging
                print("🔋 Battery level: \(battery)% \(charging ? "(Charging)" : "")")
            }
        } else {
            print("⚠️ Only received \(data.count) byte(s), expected 2 for battery")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Write error: \(error.localizedDescription)")
        } else {
            print("✅ Data written successfully")
        }
    }
}
