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
    
    // Debug data
    @Published var debugCurrentDraw: Double = 0.0  // mA
    @Published var debugVoltage: Double = 0.0      // V
    @Published var connectionStartTime: Date?
    @Published var connectionDuration: TimeInterval = 0
    
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
    private let connectionTimeout: TimeInterval = 30.0
    
    private var connectionDurationTimer: Timer?
    
    // Track if we're in the middle of connecting to prevent duplicate attempts
    private var isConnecting = false
    private var pendingConnectionDevice: UUID?
    
    // Background scanning for bonded devices list
    private var isBackgroundScanning = false
    
    // Flag to track if we should start scanning once Bluetooth is ready
    private var shouldStartScanningWhenReady = false
    
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
        // Initialize with a dedicated queue for better reliability
        let queue = DispatchQueue(label: "com.watchdog.bluetooth", qos: .userInitiated)
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }
    
    func startScanning() {
        guard isBluetoothReady else {
            print("⚠️ Cannot scan - Bluetooth not ready, will start when ready")
            shouldStartScanningWhenReady = true
            return
        }
        
        // Stop any existing scan first
        if isScanning {
            print("🔄 Already scanning, stopping first...")
            centralManager.stopScan()
        }
        
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll()
        }
        lastRSSIUpdate.removeAll()
        
        // Scan with longer timeout and allow duplicates for RSSI updates
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
        
        // Schedule stale device timer on main thread
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
            
            // Clear RSSI for bonded devices when we stop scanning
            // unless we're in background scanning mode
            if !self.isBackgroundScanning {
                BondManager.shared.clearAllRSSI()
            }
            
            self.staleDeviceTimer?.invalidate()
            self.staleDeviceTimer = nil
        }
        print("🛑 Stopped scanning")
    }
    
    func connect(to device: BluetoothDevice) {
        // Prevent duplicate connection attempts
        if isConnecting && pendingConnectionDevice == device.id {
            print("⚠️ Already connecting to this device")
            return
        }
        
        isConnecting = true
        pendingConnectionDevice = device.id
        
        print("🔌 Connecting to: \(device.name) [\(device.id.uuidString.prefix(8))]")
        
        // Stop scanning to improve connection reliability
        if isScanning {
            stopScanning()
        }
        
        // Connect with specific options for better reliability
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true,
            CBConnectPeripheralOptionStartDelayKey: 0
        ]
        
        centralManager.connect(device.peripheral, options: options)
        
        // Schedule connection timer on main thread
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
        
        // Clean up timers on main thread
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil
            
            // Stop connection duration timer
            self.connectionDurationTimer?.invalidate()
            self.connectionDurationTimer = nil
            
            // Reset state
            self.connectedDevice = nil
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
            self.lastSentData = ""
            self.deviceState = 0
            self.hasReceivedInitialState = false
            self.batteryLevel = -1
            self.isCharging = false
            self.debugCurrentDraw = 0.0
            self.debugVoltage = 0.0
            self.connectionStartTime = nil
            self.connectionDuration = 0
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
    
    // MARK: - Background Scanning for Bonded Devices
    
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
    
    private func startConnectionDurationTimer() {
        DispatchQueue.main.async {
            self.connectionStartTime = Date()
            self.connectionDuration = 0
            
            self.connectionDurationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.connectionStartTime else { return }
                self.connectionDuration = Date().timeIntervalSince(startTime)
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
                // Start scanning if we were waiting for Bluetooth to be ready
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
        
        // Throttle RSSI updates
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
        
        DispatchQueue.main.async {
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
                print("📱 Discovered: \(name) [\(deviceID.uuidString.prefix(8))] RSSI: \(RSSI.intValue)dBm")
            }
            
            // Update BondManager if this is a bonded device
            let bondManager = BondManager.shared
            if bondManager.isBonded(deviceID: deviceID) {
                bondManager.updateDeviceRSSI(deviceID: deviceID, rssi: RSSI.intValue)
                // Update name if it changed
                if let bond = bondManager.getBond(deviceID: deviceID), bond.name != name {
                    bondManager.updateDeviceName(deviceID: deviceID, name: name)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to: \(peripheral.name ?? "Unknown") [\(peripheral.identifier.uuidString.prefix(8))]")
        
        // Start connection duration timer
        startConnectionDurationTimer()
        
        // Clear connection timer on main thread
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil
            
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                // Keep the discovered name, just update connection status
                self.discoveredDevices[index] = BluetoothDevice(
                    id: peripheral.identifier,
                    name: self.discoveredDevices[index].name,  // PRESERVE THE DISCOVERED NAME
                    peripheral: peripheral,
                    rssi: self.discoveredDevices[index].rssi,
                    isConnected: true
                )
                self.connectedDevice = self.discoveredDevices[index]
            }
        }
        
        // Don't stop scanning here - let the view handle it
        
        peripheral.delegate = self
        
        // Delay service discovery slightly to ensure connection is stable
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔍 Discovering services...")
            peripheral.discoverServices([self.targetServiceUUID])
        }
    }
    
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
            self.debugCurrentDraw = 0.0
            self.debugVoltage = 0.0
            self.connectionStartTime = nil
            self.connectionDuration = 0
            
            self.connectionDurationTimer?.invalidate()
            self.connectionDurationTimer = nil
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
            
            // Read initial value if readable
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
        
        // Debug: print all received bytes
        print("📦 Received \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // Parse based on packet length
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
        }
        
        // Read debug data if available (bytes 2-5: current + voltage)
        if data.count >= 6 {
            // Bytes 2-3: Current in mA (little-endian, SIGNED)
            let currentLow = UInt16(data[2])
            let currentHigh = UInt16(data[3])
            let currentRaw = currentLow | (currentHigh << 8)
            // Reinterpret as signed int16 (negative = charging, positive = discharging)
            let current = Double(Int16(bitPattern: currentRaw))
            
            // Bytes 4-5: Voltage in mV (little-endian)
            let voltageLow = UInt16(data[4])
            let voltageHigh = UInt16(data[5])
            let voltageRaw = voltageLow | (voltageHigh << 8)
            let voltage = Double(voltageRaw) / 1000.0  // Convert mV to V
            
            DispatchQueue.main.async {
                self.debugCurrentDraw = current
                self.debugVoltage = voltage
                print("🔧 Debug - Current: \(current)mA, Voltage: \(voltage)V")
            }
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
