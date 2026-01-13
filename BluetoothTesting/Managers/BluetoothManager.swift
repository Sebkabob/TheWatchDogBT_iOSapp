//
//  BluetoothManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation
import CoreBluetooth

// Command definitions matching firmware
enum WatchDogCommand: UInt8 {
    case requestLogCount = 0xF0
    case requestEvent = 0xF1
    case clearLog = 0xF2
    case ackEvent = 0xF3
}

// Response types matching firmware
enum WatchDogResponse: UInt8 {
    case logCount = 0xE0
    case eventData = 0xE1
    case noMoreEvents = 0xE2
    case logCleared = 0xE3
}

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
    @Published var isSyncingMotionLogs = false
    @Published var syncProgress: Float = 0.0
    
    private let settingsManager = SettingsManager.shared
    private let motionLogManager = MotionLogManager.shared
    
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private let targetServiceUUID = CBUUID(string: "183E")
    
    private var lastRSSIUpdate: [UUID: Date] = [:]
    private let rssiUpdateInterval: TimeInterval = 1.0
    
    private let deviceTimeout: TimeInterval = 5.0
    private var staleDeviceTimer: Timer?
    
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 30.0
    
    private var isConnecting = false
    private var pendingConnectionDevice: UUID?
    
    private var isBackgroundScanning = false
    
    private var shouldStartScanningWhenReady = false
    
    // Motion log sync state
    private var expectedEventCount: UInt16 = 0
    private var receivedEventCount: UInt16 = 0
    
    var deviceStateText: String {
        let isArmed = (deviceState & 0x01) != 0
        
        if isArmed {
            return "Locked"
        } else {
            return "Unlocked"
        }
    }
    
    override init() {
        super.init()
        let queue = DispatchQueue(label: "com.watchdog.bluetooth", qos: .userInitiated)
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }
    
    func startScanning() {
        guard isBluetoothReady else {
            print("⚠️ Cannot scan - Bluetooth not ready, will start when ready")
            shouldStartScanningWhenReady = true
            return
        }
        
        if isScanning {
            print("🔄 Already scanning, stopping first...")
            centralManager.stopScan()
        }
        
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll()
        }
        lastRSSIUpdate.removeAll()
        
        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [targetServiceUUID]
            ]
        )
        
        DispatchQueue.main.async {
            self.isScanning = true
        }
        
        print("✅ Started scanning for 0x183E devices")
        
        DispatchQueue.main.async {
            self.staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.removeStaleDevices()
            }
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        DispatchQueue.main.async {
            self.isScanning = false
            
            if !self.isBackgroundScanning {
                BondManager.shared.clearAllRSSI()
            }
            
            self.staleDeviceTimer?.invalidate()
            self.staleDeviceTimer = nil
        }
        print("🛑 Stopped scanning")
    }
    
    func connect(to device: BluetoothDevice) {
        if isConnecting && pendingConnectionDevice == device.id {
            print("⚠️ Already connecting to this device")
            return
        }
        
        isConnecting = true
        pendingConnectionDevice = device.id
        
        print("🔌 Connecting to: \(device.name) [\(device.id.uuidString.prefix(8))]")
        
        if isScanning {
            stopScanning()
        }
        
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true,
            CBConnectPeripheralOptionStartDelayKey: 0
        ]
        
        centralManager.connect(device.peripheral, options: options)
        
        DispatchQueue.main.async {
            self.connectionTimer = Timer.scheduledTimer(withTimeInterval: self.connectionTimeout, repeats: false) { [weak self] _ in
                print("⏱️ Connection timeout for \(device.name)")
                self?.centralManager.cancelPeripheralConnection(device.peripheral)
                self?.connectionTimer = nil
                self?.isConnecting = false
                self?.pendingConnectionDevice = nil
            }
        }
    }
    
    func disconnect(from device: BluetoothDevice) {
        print("🔌 Disconnecting from: \(device.name)")
        centralManager.cancelPeripheralConnection(device.peripheral)
        
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil
            
            self.connectedDevice = nil
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
            self.lastSentData = ""
            self.deviceState = 0
            self.hasReceivedInitialState = false
            self.batteryLevel = -1
            self.isCharging = false
            self.isSyncingMotionLogs = false
            self.syncProgress = 0.0
            self.expectedEventCount = 0
            self.receivedEventCount = 0
        }
    }
    
    func sendData(_ data: Data) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedDevice?.peripheral else {
            print("❌ No writable characteristic found")
            return
        }
        
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        DispatchQueue.main.async {
            self.lastSentData = "0x\(hexString) (\(data.count) bytes)"
        }
        print("📤 Sent: 0x\(hexString) (\(data.count) bytes)")
    }
    
    func sendSettings() {
        let settingsByte = settingsManager.encodeSettings()
        let data = Data([settingsByte])
        sendData(data)
        print("📤 Sent settings byte: 0x\(String(format: "%02X", settingsByte))")
    }
    
    // MARK: - Motion Log Sync Methods
    
    func requestMotionLogCount() {
        guard connectedDevice != nil else {
            print("❌ Not connected to device")
            return
        }
        
        print("📤 Requesting motion log count...")
        let command = Data([WatchDogCommand.requestLogCount.rawValue])
        sendData(command)
        
        DispatchQueue.main.async {
            self.isSyncingMotionLogs = true
            self.syncProgress = 0.0
            self.receivedEventCount = 0
        }
    }
    
    func requestEvent(atIndex index: UInt16) {
        guard connectedDevice != nil else { return }
        
        let highByte = UInt8((index >> 8) & 0xFF)
        let lowByte = UInt8(index & 0xFF)
        
        let command = Data([WatchDogCommand.requestEvent.rawValue, highByte, lowByte])
        sendData(command)
        print("📤 Requesting event at index \(index)")
    }
    
    func clearMotionLogs() {
        guard connectedDevice != nil else { return }
        
        print("📤 Requesting to clear motion logs...")
        let command = Data([WatchDogCommand.clearLog.rawValue])
        sendData(command)
    }
    
    private func handleMotionLogCount(data: Data) {
        guard data.count >= 3 else {
            print("❌ Invalid log count data length: \(data.count)")
            return
        }
        
        let highByte = UInt16(data[1])
        let lowByte = UInt16(data[2])
        expectedEventCount = (highByte << 8) | lowByte
        
        print("📥 Received event count: \(expectedEventCount)")
        
        DispatchQueue.main.async {
            self.expectedEventCount = self.expectedEventCount
        }
        
        if expectedEventCount == 0 {
            print("✅ No events to sync")
            DispatchQueue.main.async {
                self.isSyncingMotionLogs = false
                self.syncProgress = 1.0
            }
            return
        }
        
        // Start requesting events
        requestEvent(atIndex: 0)
    }
    
    private func handleEventData(data: Data) {
        guard data.count >= 10 else {
            print("❌ Invalid event data length: \(data.count)")
            return
        }
        
        let highByte = UInt16(data[1])
        let lowByte = UInt16(data[2])
        let eventIndex = (highByte << 8) | lowByte
        
        // Parse event data from firmware
        let year = data[3]
        let month = data[4]
        let day = data[5]
        let hour = data[6]
        let minute = data[7]
        let second = data[8]
        let motionTypeByte = data[9]
        
        // Convert to timestamp
        var dateComponents = DateComponents()
        dateComponents.year = 2000 + Int(year)  // Firmware sends year offset from 2000
        dateComponents.month = Int(month)
        dateComponents.day = Int(day)
        dateComponents.hour = Int(hour)
        dateComponents.minute = Int(minute)
        dateComponents.second = Int(second)
        
        let calendar = Calendar.current
        guard let timestamp = calendar.date(from: dateComponents) else {
            print("❌ Failed to create date from components")
            return
        }
        
        // Use MotionTypeConfig to convert firmware type to iOS type
        let (eventType, alarmSounded) = MotionTypeConfig.convert(firmwareType: motionTypeByte)
        
        let motionEvent = MotionEvent(
            timestamp: timestamp,
            eventType: eventType,
            alarmSounded: alarmSounded
        )
        
        motionLogManager.addMotionEvent(motionEvent)
        
        DispatchQueue.main.async {
            self.receivedEventCount += 1
            self.syncProgress = Float(self.receivedEventCount) / Float(self.expectedEventCount)
        }
        
        print("📥 Received event \(eventIndex + 1)/\(expectedEventCount): \(eventType.displayName)")
        
        // Request next event
        let nextIndex = eventIndex + 1
        if nextIndex < expectedEventCount {
            // Small delay to avoid overwhelming the device
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.requestEvent(atIndex: nextIndex)
            }
        } else {
            // All events received
            print("✅ All motion events synced!")
            DispatchQueue.main.async {
                self.isSyncingMotionLogs = false
                self.syncProgress = 1.0
            }
        }
    }
    
    private func handleNoMoreEvents(data: Data) {
        guard data.count >= 3 else { return }
        
        let highByte = UInt16(data[1])
        let lowByte = UInt16(data[2])
        let requestedIndex = (highByte << 8) | lowByte
        
        print("⚠️ No event at index \(requestedIndex)")
        
        DispatchQueue.main.async {
            self.isSyncingMotionLogs = false
        }
    }
    
    private func handleLogCleared(data: Data) {
        print("✅ Motion logs cleared on WatchDog")
        
        DispatchQueue.main.async {
            self.isSyncingMotionLogs = false
            self.syncProgress = 0.0
            self.expectedEventCount = 0
            self.receivedEventCount = 0
        }
    }
    
    // MARK: - Background Scanning
    
    func startBackgroundScanning() {
        guard !isBackgroundScanning else {
            print("⚠️ Background scanning already active")
            return
        }
        
        isBackgroundScanning = true
        startScanning()
        print("🔍 Started background scanning for bonded devices")
    }
    
    func stopBackgroundScanning() {
        guard isBackgroundScanning else { return }
        
        isBackgroundScanning = false
        stopScanning()
        print("🛑 Stopped background scanning")
    }
    
    private func removeStaleDevices() {
        let now = Date()
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { device in
                guard let lastUpdate = self.lastRSSIUpdate[device.id] else {
                    return true
                }
                let isStale = now.timeIntervalSince(lastUpdate) > self.deviceTimeout
                if isStale {
                    print("🗑️ Removing stale device: \(device.name)")
                    self.lastRSSIUpdate.removeValue(forKey: device.id)
                }
                return isStale
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.isBluetoothReady = central.state == .poweredOn
            
            switch central.state {
            case .poweredOn:
                print("✅ Bluetooth powered on")
                if self.shouldStartScanningWhenReady {
                    self.shouldStartScanningWhenReady = false
                    print("🔄 Bluetooth ready - starting pending scan")
                    self.startScanning()
                }
            case .poweredOff:
                print("❌ Bluetooth powered off")
            case .unauthorized:
                print("⚠️ Bluetooth unauthorized")
            case .unsupported:
                print("❌ Bluetooth unsupported")
            case .resetting:
                print("🔄 Bluetooth resetting")
            case .unknown:
                print("❓ Bluetooth state unknown")
            @unknown default:
                print("❓ Bluetooth state unknown")
            }
        }
        
        if !isBluetoothReady {
            stopScanning()
            DispatchQueue.main.async {
                self.connectedDevice = nil
            }
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
        
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "WatchDog"
        
        let device = BluetoothDevice(
            id: deviceID,
            name: name,
            peripheral: peripheral,
            rssi: RSSI.intValue,
            isConnected: false
        )
        
        DispatchQueue.main.async {
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
                print("📱 Discovered: \(name) [\(deviceID.uuidString.prefix(8))] RSSI: \(RSSI.intValue)dBm")
            }
            
            let bondManager = BondManager.shared
            if bondManager.isBonded(deviceID: deviceID) {
                bondManager.updateDeviceRSSI(deviceID: deviceID, rssi: RSSI.intValue)
                if let bond = bondManager.getBond(deviceID: deviceID), bond.name != name {
                    bondManager.updateDeviceName(deviceID: deviceID, name: name)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to: \(peripheral.name ?? "Unknown") [\(peripheral.identifier.uuidString.prefix(8))]")
        
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil
            
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[index] = BluetoothDevice(
                    id: peripheral.identifier,
                    name: self.discoveredDevices[index].name,
                    peripheral: peripheral,
                    rssi: self.discoveredDevices[index].rssi,
                    isConnected: true
                )
                self.connectedDevice = self.discoveredDevices[index]
            }
        }
        
        peripheral.delegate = self
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔍 Discovering services...")
            peripheral.discoverServices([self.targetServiceUUID])
        }
    }a
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            print("❌ Disconnected from: \(peripheral.name ?? "Unknown") - Error: \(error.localizedDescription)")
        } else {
            print("🔌 Disconnected from: \(peripheral.name ?? "Unknown")")
        }
        
        DispatchQueue.main.async {
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[index].isConnected = false
            }
            
            self.connectedDevice = nil
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
            self.lastSentData = ""
            self.deviceState = 0
            self.hasReceivedInitialState = false
            self.batteryLevel = -1
            self.isCharging = false
            self.isConnecting = false
            self.pendingConnectionDevice = nil
            self.isSyncingMotionLogs = false
            self.syncProgress = 0.0
            self.expectedEventCount = 0
            self.receivedEventCount = 0
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("⚠️ No services found")
            return
        }
        
        print("📋 Found \(services.count) service(s)")
        for service in services {
            print("  🔹 Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            print("⚠️ No characteristics found")
            return
        }
        
        print("📋 Found \(characteristics.count) characteristic(s) for service \(service.uuid)")
        
        for characteristic in characteristics {
            print("  🔹 Characteristic: \(characteristic.uuid)")
            print("     Properties: \(characteristic.properties)")
            
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                print("     ✅ This is writable! Ready to send data.")
            }
            
            if characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("     ✅ Subscribed to notifications!")
            }
            
            if characteristic.properties.contains(.read) {
                print("     📖 Reading initial value...")
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error updating notification state: \(error.localizedDescription)")
            return
        }
        
        if characteristic.isNotifying {
            print("✅ Notifications enabled for \(characteristic.uuid)")
        } else {
            print("⚠️ Notifications disabled for \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error reading characteristic: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            print("⚠️ No data received")
            return
        }
        
        print("📦 Received \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Check if this is a motion log response
        if data.count > 0 {
            let responseType = data[0]
            
            switch responseType {
            case WatchDogResponse.logCount.rawValue:
                handleMotionLogCount(data: data)
                return
                
            case WatchDogResponse.eventData.rawValue:
                handleEventData(data: data)
                return
                
            case WatchDogResponse.noMoreEvents.rawValue:
                handleNoMoreEvents(data: data)
                return
                
            case WatchDogResponse.logCleared.rawValue:
                handleLogCleared(data: data)
                return
                
            default:
                break
            }
        }
        
        // Handle regular state/battery data
        if data.count >= 1 {
            let settingsByte = data[0]
            
            DispatchQueue.main.async {
                let oldState = self.deviceState
                self.deviceState = settingsByte
                self.hasReceivedInitialState = true
                
                self.settingsManager.decodeSettings(from: settingsByte)
                
                print("📥 Received device state: 0x\(String(format: "%02X", settingsByte)) - \(self.deviceStateText) (was: 0x\(String(format: "%02X", oldState)))")
            }
        }
        
        if data.count >= 2 {
            let batteryByte = data[1]
            
            let charging = (batteryByte & 0x80) != 0
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
            print("✅ Data written successfully to \(characteristic.uuid)")
        }
    }
}
