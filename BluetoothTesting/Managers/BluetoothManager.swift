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
    @Published var isBackgroundScanning = false
    @Published var isBluetoothReady = false
    @Published var connectedDevice: BluetoothDevice?
    @Published var lastSentData: String = ""
    @Published var deviceState: UInt8 = 0
    @Published var hasReceivedInitialState = false
    @Published var batteryLevel: Int = -1
    
    private let settingsManager = SettingsManager.shared
    private let bondManager = BondManager.shared
    
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
        let isArmed = (deviceState & 0x01) != 0
        return isArmed ? "Locked" : "Unlocked"
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        guard isBluetoothReady else { return }
        discoveredDevices.removeAll()
        lastRSSIUpdate.removeAll()
        
        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        print("📡 Started active scanning for 0x183E devices")
        
        staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.removeStaleDevices()
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        staleDeviceTimer?.invalidate()
        staleDeviceTimer = nil
        print("📡 Stopped active scanning")
    }
    
    func startBackgroundScanning() {
        guard isBluetoothReady else { return }
        
        // Only scan for bonded devices
        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isBackgroundScanning = true
        print("🔍 Started background scanning for bonded devices")
        
        staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.removeStaleDevices()
            self?.updateBondedDevicesRSSI()
        }
    }
    
    func stopBackgroundScanning() {
        if !isScanning {  // Don't stop if active scanning
            centralManager.stopScan()
        }
        isBackgroundScanning = false
        staleDeviceTimer?.invalidate()
        staleDeviceTimer = nil
        bondManager.clearAllRSSI()
        print("🔍 Stopped background scanning")
    }
    
    private func updateBondedDevicesRSSI() {
        // Update bonded devices with current RSSI
        for device in discoveredDevices {
            if bondManager.isBonded(deviceID: device.id) {
                bondManager.updateDeviceRSSI(deviceID: device.id, rssi: device.rssi)
            }
        }
        
        // Clear RSSI for bonded devices not in discovered list
        for bondedDevice in bondManager.bondedDevices {
            if !discoveredDevices.contains(where: { $0.id == bondedDevice.id }) {
                bondManager.clearRSSI(deviceID: bondedDevice.id)
            }
        }
    }
    
    // MARK: - Connection
    
    func connect(to device: BluetoothDevice) {
        print("🔗 Connecting to: \(device.name)")
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
        print("🔌 Disconnected from \(device.name)")
    }
    
    // MARK: - Data Transmission
    
    func sendData(_ data: Data) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedDevice?.peripheral else {
            print("❌ No writable characteristic found")
            return
        }
        
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        lastSentData = "0x\(hexString) (\(data.count) bytes)"
        print("📤 Sent: \(lastSentData)")
    }
    
    func sendSettings() {
        let settingsByte = settingsManager.encodeSettings()
        let data = Data([settingsByte])
        sendData(data)
        print("📤 Sent settings byte: 0x\(String(format: "%02X", settingsByte))")
    }
    
    // MARK: - Private Helpers
    
    private func removeStaleDevices() {
        let now = Date()
        discoveredDevices.removeAll { device in
            guard let lastUpdate = lastRSSIUpdate[device.id] else {
                return true
            }
            let isStale = now.timeIntervalSince(lastUpdate) > deviceTimeout
            if isStale {
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
            stopBackgroundScanning()
            connectedDevice = nil
        }
        
        print("📱 Bluetooth state: \(central.state.rawValue)")
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceID = peripheral.identifier
        let now = Date()
        
        // Throttle RSSI updates
        if let lastUpdate = lastRSSIUpdate[deviceID] {
            if now.timeIntervalSince(lastUpdate) < rssiUpdateInterval {
                return
            }
        }
        
        lastRSSIUpdate[deviceID] = now
        
        // Prioritize advertised name from peripheral, then from advertisement data, then fallback
        var name = peripheral.name ?? "WatchDog"
        
        // Check if advertisement data has a local name
        if let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !advertisedName.isEmpty {
            name = advertisedName
        }
        
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
        }
        
        // Update bonded device RSSI if background scanning
        if isBackgroundScanning && bondManager.isBonded(deviceID: deviceID) {
            bondManager.updateDeviceRSSI(deviceID: deviceID, rssi: RSSI.intValue)
            // Also update the name in case the device advertises a different name
            bondManager.updateDeviceName(deviceID: deviceID, name: name)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to: \(peripheral.name ?? "Unknown")")
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].isConnected = true
            connectedDevice = discoveredDevices[index]
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([targetServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("🔌 Disconnected from: \(peripheral.name ?? "Unknown")")
        
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
            print("🔍 Discovered service: \(service.uuid)")
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
            print("🔍 Found characteristic: \(characteristic.uuid)")
            
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                print("  ✅ Writable characteristic found")
            }
            
            if characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("  ✅ Subscribed to notifications")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error reading characteristic: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else { return }
        
        if data.count >= 1 {
            let settingsByte = data[0]
            
            DispatchQueue.main.async {
                self.deviceState = settingsByte
                self.hasReceivedInitialState = true
                self.settingsManager.decodeSettings(from: settingsByte)
                print("📥 Received device state: 0x\(String(format: "%02X", settingsByte)) - \(self.deviceStateText)")
            }
        }
        
        if data.count >= 2 {
            let battery = Int(data[1])
            DispatchQueue.main.async {
                self.batteryLevel = battery
                print("🔋 Battery level: \(battery)%")
            }
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
