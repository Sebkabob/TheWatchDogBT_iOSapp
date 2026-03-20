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
    
    // Motion log sync state
    @Published var pendingEventCount: Int = 0
    @Published var isSyncingMotionLogs: Bool = false
    
    private let settingsManager = SettingsManager.shared
    
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private let targetServiceUUID = CBUUID(string: "183E")
    
    private var lastRSSIUpdate: [UUID: Date] = [:]
    private let rssiUpdateInterval: TimeInterval = 1.0
    
    private let deviceTimeout: TimeInterval = 8.0
    private var staleDeviceTimer: Timer?
    
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 30.0
    
    private var connectionDurationTimer: Timer?
    
    // Track if we're in the middle of connecting to prevent duplicate attempts
    private(set) var isConnecting = false
    private var pendingConnectionDevice: UUID?
    
    // Background scanning for bonded devices list
    private var isBackgroundScanning = false
    
    // Flag to track if we should start scanning once Bluetooth is ready
    private var shouldStartScanningWhenReady = false
    
    // Reconnection support
    private var reconnectTargetDeviceID: UUID?
    @Published var isAttemptingReconnect = false
    
    // Flag to suppress auto-reconnect after user-initiated disconnect
    var suppressAutoReconnect = false
    
    // Scan health monitoring — restarts scan if it silently dies
    private var scanHealthTimer: Timer?
    private var lastAdvertisementReceived: Date?
    private let scanHealthCheckInterval: TimeInterval = 6.0   // check every 6s
    private let scanStaleThreshold: TimeInterval = 10.0        // restart if no ads for 10s
    
    // Motion log response opcodes (must match firmware definitions)
    private let RESP_LOG_COUNT: UInt8       = 0xE0
    private let RESP_EVENT_DATA: UInt8      = 0xE1
    private let RESP_NO_MORE_EVENTS: UInt8  = 0xE2
    private let RESP_LOG_CLEARED: UInt8     = 0xE3
    private let MOTION_ALERT_MARKER: UInt8  = 0xFF
    
    // Motion log command opcodes
    private let CMD_REQUEST_LOG_COUNT: UInt8 = 0xF0
    private let CMD_REQUEST_EVENT: UInt8     = 0xF1
    private let CMD_CLEAR_LOG: UInt8         = 0xF2
    private let CMD_ACK_EVENT: UInt8         = 0xF3
    
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
            self.lastAdvertisementReceived = Date()
        }
        
        print("✅ Started scanning for 0x183E devices")
        
        DispatchQueue.main.async {
            self.staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.removeStaleDevices()
            }
        }
        
        startScanHealthMonitor()
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
        
        stopScanHealthMonitor()
        
        print("🛑 Stopped scanning")
    }
    
    func connect(to device: BluetoothDevice) {
        if isConnecting && pendingConnectionDevice == device.id {
            print("⚠️ Already connecting to this device")
            return
        }
        
        // Clear the suppress flag when explicitly connecting
        suppressAutoReconnect = false
        
        isConnecting = true
        pendingConnectionDevice = device.id
        
        print("🔌 Connecting to: \(device.name) [\(device.id.uuidString.prefix(8))]")
        
        if isScanning && !isAttemptingReconnect {
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
        
        // Set suppress flag so background scanning doesn't auto-reconnect
        suppressAutoReconnect = true
        
        centralManager.cancelPeripheralConnection(device.peripheral)
        
        // Stop reconnection attempts
        stopReconnecting()
        
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil
            
            self.connectionDurationTimer?.invalidate()
            self.connectionDurationTimer = nil
            
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
            self.pendingEventCount = 0
            self.isSyncingMotionLogs = false
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
    
    // MARK: - Motion Log Sync
    
    /// Request the total count of motion events stored on firmware
    func requestMotionLogCount() {
        guard connectedDevice != nil else {
            print("❌ Cannot request motion log count - not connected")
            return
        }
        
        DispatchQueue.main.async {
            self.isSyncingMotionLogs = true
        }
        
        let data = Data([CMD_REQUEST_LOG_COUNT])
        sendData(data)
        print("📤 Requested motion log count")
    }
    
    /// Request a specific motion event by index
    func requestMotionEvent(at index: UInt16) {
        let data = Data([CMD_REQUEST_EVENT, UInt8((index >> 8) & 0xFF), UInt8(index & 0xFF)])
        sendData(data)
        print("📤 Requested motion event at index \(index)")
    }
    
    /// Tell firmware to clear its motion log
    func clearMotionLog() {
        let data = Data([CMD_CLEAR_LOG])
        sendData(data)
        print("📤 Requested motion log clear")
    }
    
    /// Handle incoming motion log response packets from firmware
    private func handleMotionLogResponse(data: Data) {
        guard data.count >= 1 else { return }
        
        let responseType = data[0]
        
        switch responseType {
        case RESP_LOG_COUNT:
            // Format: [0xE0] [countHigh] [countLow]
            guard data.count >= 3 else {
                print("❌ RESP_LOG_COUNT packet too short: \(data.count) bytes")
                return
            }
            let count = (UInt16(data[1]) << 8) | UInt16(data[2])
            print("📥 Motion log count: \(count)")
            
            DispatchQueue.main.async {
                self.pendingEventCount = Int(count)
                
                if count > 0 {
                    // Start requesting events one by one, starting at index 0
                    self.requestMotionEvent(at: 0)
                } else {
                    print("✅ No motion events to sync")
                    self.isSyncingMotionLogs = false
                }
            }
            
        case RESP_EVENT_DATA:
            // Format: [0xE1] [indexHigh] [indexLow] [year] [month] [day] [hour] [minute] [second] [motionType] [battery]
            guard data.count >= 10 else {
                print("❌ RESP_EVENT_DATA packet too short: \(data.count) bytes")
                return
            }
            let index = (UInt16(data[1]) << 8) | UInt16(data[2])
            let year = data[3]
            let month = data[4]
            let day = data[5]
            let hour = data[6]
            let minute = data[7]
            let second = data[8]
            let motionType = data[9]
            
            // Build date from firmware RTC timestamp
            var timestamp: Date
            
            if year == 0 && month <= 1 && day <= 1 {
                timestamp = Date()
                print("⚠️ Firmware RTC not set (year=0), using current iOS time for event")
            } else {
                var components = DateComponents()
                components.year = 2000 + Int(year)
                components.month = max(1, Int(month))
                components.day = max(1, Int(day))
                components.hour = Int(hour)
                components.minute = Int(minute)
                components.second = Int(second)
                
                let calendar = Calendar.current
                timestamp = calendar.date(from: components) ?? Date()
            }
            
            // Convert firmware motion type to iOS event type
            let config = MotionTypeConfig.convert(firmwareType: motionType)
            let event = MotionEvent(
                timestamp: timestamp,
                eventType: config.eventType,
                alarmSounded: config.alarmSounded
            )
            
            DispatchQueue.main.async {
                MotionLogManager.shared.addMotionEvent(event)
                print("📥 Motion event \(index): \(event.eventType.displayName) at \(timestamp)")
                
                // Acknowledge receipt
                let ackData = Data([self.CMD_ACK_EVENT, UInt8((index >> 8) & 0xFF), UInt8(index & 0xFF)])
                self.sendData(ackData)
                
                // Request next event
                let nextIndex = index + 1
                if nextIndex < UInt16(self.pendingEventCount) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.requestMotionEvent(at: nextIndex)
                    }
                } else {
                    print("✅ All \(self.pendingEventCount) motion events synced")
                    self.clearMotionLog()
                    self.isSyncingMotionLogs = false
                }
            }
            
        case RESP_NO_MORE_EVENTS:
            if data.count >= 3 {
                let index = (UInt16(data[1]) << 8) | UInt16(data[2])
                print("📥 No more motion events (requested index \(index))")
            } else {
                print("📥 No more motion events")
            }
            DispatchQueue.main.async {
                self.isSyncingMotionLogs = false
            }
            
        case RESP_LOG_CLEARED:
            print("📥 Motion log cleared on device")
            DispatchQueue.main.async {
                self.pendingEventCount = 0
                self.isSyncingMotionLogs = false
            }
            
        default:
            print("⚠️ Unknown motion log response: 0x\(String(format: "%02X", responseType))")
        }
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
        
        // Don't stop scanning if we're reconnecting
        if !isAttemptingReconnect {
            stopScanning()
        }
        print("🛑 Stopped background scanning")
    }
    
    // MARK: - Scan Health Monitoring
    
    private func startScanHealthMonitor() {
        stopScanHealthMonitor()
        
        DispatchQueue.main.async {
            self.scanHealthTimer = Timer.scheduledTimer(withTimeInterval: self.scanHealthCheckInterval, repeats: true) { [weak self] _ in
                self?.checkScanHealth()
            }
        }
        print("🏥 Scan health monitor started")
    }
    
    private func stopScanHealthMonitor() {
        DispatchQueue.main.async {
            self.scanHealthTimer?.invalidate()
            self.scanHealthTimer = nil
        }
    }
    
    private func checkScanHealth() {
        // Only check if we expect to be scanning
        guard isScanning || isBackgroundScanning else { return }
        guard isBluetoothReady else { return }
        // Don't restart scan while actively connected — we don't need advertisements
        guard connectedDevice == nil else { return }
        
        // If we have bonded devices, we expect to see advertisements
        let hasBondedDevices = !BondManager.shared.bondedDevices.isEmpty
        guard hasBondedDevices else { return }
        
        if let lastAd = lastAdvertisementReceived {
            let timeSinceLastAd = Date().timeIntervalSince(lastAd)
            if timeSinceLastAd > scanStaleThreshold {
                print("🏥 Scan health: No advertisements for \(String(format: "%.1f", timeSinceLastAd))s — restarting scan")
                restartScan()
            }
        } else {
            // Never received an advertisement since scan started — restart
            print("🏥 Scan health: No advertisements ever received — restarting scan")
            restartScan()
        }
    }
    
    /// Force-restart the BLE scan to recover from silent scan death
    private func restartScan() {
        guard isBluetoothReady else { return }
        
        centralManager.stopScan()
        
        // Small delay before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.isBluetoothReady else { return }
            
            self.centralManager.scanForPeripherals(
                withServices: [self.targetServiceUUID],
                options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true,
                    CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [self.targetServiceUUID]
                ]
            )
            
            self.isScanning = true
            self.lastAdvertisementReceived = Date()
            print("🏥 Scan restarted successfully")
        }
    }
    
    // MARK: - Reconnection Support
    
    func startReconnecting(to deviceID: UUID) {
        // Don't reconnect if user explicitly disconnected
        guard !suppressAutoReconnect else {
            print("⚠️ Auto-reconnect suppressed (user disconnected)")
            return
        }
        
        // Don't start if already reconnecting to this device
        if isAttemptingReconnect && reconnectTargetDeviceID == deviceID {
            print("⚠️ Already attempting reconnection to this device")
            return
        }
        
        reconnectTargetDeviceID = deviceID
        
        DispatchQueue.main.async {
            self.isAttemptingReconnect = true
        }
        
        print("🔄 Starting reconnection attempts for \(deviceID.uuidString.prefix(8))")
        
        // Ensure scanning is active — this is critical for reconnection.
        // The scan with AllowDuplicates will fire didDiscover every time
        // the device advertises (~1/sec), and we connect immediately from there.
        ensureScanningForReconnect()
    }
    
    func stopReconnecting() {
        let wasReconnecting = isAttemptingReconnect
        
        DispatchQueue.main.async {
            self.reconnectTargetDeviceID = nil
            self.isAttemptingReconnect = false
        }
        
        if wasReconnecting {
            print("🛑 Stopped reconnection attempts")
        }
    }
    
    /// Ensure BLE scanning is active for reconnection purposes.
    /// If already scanning, this is a no-op. If not, starts a scan.
    private func ensureScanningForReconnect() {
        guard isBluetoothReady else {
            shouldStartScanningWhenReady = true
            print("⚠️ Bluetooth not ready, will scan when ready for reconnect")
            return
        }
        
        if isScanning {
            print("🔍 Already scanning — reconnect will use existing scan")
            return
        }
        
        // Start scanning specifically for reconnection
        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [targetServiceUUID]
            ]
        )
        
        DispatchQueue.main.async {
            self.isScanning = true
            self.lastAdvertisementReceived = Date()
        }
        
        startScanHealthMonitor()
        
        print("🔍 Started scanning for reconnection target")
    }
    
    /// Called from didDiscover — if we're reconnecting and this is our target, connect immediately.
    /// This is the KEY change: we don't poll on a timer, we react instantly to advertisement.
    private func tryImmediateReconnect(device: BluetoothDevice) {
        guard isAttemptingReconnect,
              let targetID = reconnectTargetDeviceID,
              device.id == targetID,
              !suppressAutoReconnect,
              connectedDevice == nil,
              !isConnecting else {
            return
        }
        
        print("🔄 Target device discovered during reconnect — connecting immediately!")
        connect(to: device)
    }
    
    private func removeStaleDevices() {
        let now = Date()
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { device in
                // Don't remove the reconnect target device — we need its peripheral reference
                if self.isAttemptingReconnect && device.id == self.reconnectTargetDeviceID {
                    return false
                }
                
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
                if self.shouldStartScanningWhenReady {
                    self.shouldStartScanningWhenReady = false
                    print("🔄 Bluetooth ready - starting pending scan")
                    self.startScanning()
                }
                // If we were reconnecting, make sure scan resumes
                if self.isAttemptingReconnect {
                    self.ensureScanningForReconnect()
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
        
        // Track that we received an advertisement (for scan health monitoring)
        lastAdvertisementReceived = now
        
        // During reconnection, skip the RSSI throttle for our target device
        // so we can react to every single advertisement immediately
        let isReconnectTarget = isAttemptingReconnect && deviceID == reconnectTargetDeviceID
        
        // Skip RSSI throttle for bonded devices — they must always update lastSeen
        // so the UI shows them as "in range" without delay
        let isBondedDevice = BondManager.shared.isBonded(deviceID: deviceID)
        
        if !isReconnectTarget && !isBondedDevice {
            if let lastUpdate = lastRSSIUpdate[deviceID] {
                if now.timeIntervalSince(lastUpdate) < rssiUpdateInterval {
                    return
                }
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
            
            // IMMEDIATE reconnection: if this is our target device, connect right now
            self.tryImmediateReconnect(device: device)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to: \(peripheral.name ?? "Unknown") [\(peripheral.identifier.uuidString.prefix(8))]")
        
        startConnectionDurationTimer()
        stopReconnecting()
        
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil
            self.suppressAutoReconnect = false
            
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[index] = BluetoothDevice(
                    id: peripheral.identifier,
                    name: self.discoveredDevices[index].name,
                    peripheral: peripheral,
                    rssi: self.discoveredDevices[index].rssi,
                    isConnected: true
                )
                self.connectedDevice = self.discoveredDevices[index]
            } else {
                let device = BluetoothDevice(
                    id: peripheral.identifier,
                    name: peripheral.name ?? "WatchDog",
                    peripheral: peripheral,
                    rssi: -50,
                    isConnected: true
                )
                self.discoveredDevices.append(device)
                self.connectedDevice = device
            }
        }
        
        peripheral.delegate = self
        
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
            self.pendingEventCount = 0
            self.isSyncingMotionLogs = false
            
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
            
            // If we're reconnecting, we should keep trying — the scan is still active
            // and the next advertisement will trigger another attempt
            if self.isAttemptingReconnect {
                print("🔄 Connection failed but still reconnecting — will retry on next advertisement")
            }
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
        
        // After characteristics are discovered, trigger motion log sync after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.connectedDevice != nil else { return }
            print("📋 Auto-syncing motion logs after connection...")
            self.requestMotionLogCount()
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
        
        guard data.count >= 1 else { return }
        
        let firstByte = data[0]
        
        // ─── Check if this is a motion alert (0xFF) ───
        if firstByte == MOTION_ALERT_MARKER {
            print("🚨 Motion alert received from device!")
            if data.count >= 2 {
                let batteryByte = data[1]
                let charging = (batteryByte & 0x80) != 0
                let battery = Int(batteryByte & 0x7F)
                DispatchQueue.main.async {
                    self.batteryLevel = battery
                    self.isCharging = charging
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.requestMotionLogCount()
            }
            return
        }
        
        // ─── Check if this is a motion log response (0xE0–0xE3) ───
        if firstByte >= 0xE0 && firstByte <= 0xE3 {
            handleMotionLogResponse(data: data)
            return
        }
        
        // ─── Otherwise it's a regular status update ───
        let settingsByte = firstByte
        
        DispatchQueue.main.async {
            let oldState = self.deviceState
            self.deviceState = settingsByte
            self.hasReceivedInitialState = true
            
            self.settingsManager.decodeSettings(from: settingsByte)
            
            print("📥 Received device state: 0x\(String(format: "%02X", settingsByte)) - \(self.deviceStateText) (was: 0x\(String(format: "%02X", oldState)))")
        }
        
        // Byte 1: battery level
        if data.count >= 2 {
            let batteryByte = data[1]
            let charging = (batteryByte & 0x80) != 0
            let battery = Int(batteryByte & 0x7F)
            
            DispatchQueue.main.async {
                self.batteryLevel = battery
                self.isCharging = charging
                print("🔋 Battery level: \(battery)% \(charging ? "(Charging)" : "")")
            }
        }
        
        // Bytes 2-5: debug data
        if data.count >= 6 {
            let currentLow = UInt16(data[2])
            let currentHigh = UInt16(data[3])
            let currentRaw = currentLow | (currentHigh << 8)
            let current = Double(Int16(bitPattern: currentRaw))
            
            let voltageLow = UInt16(data[4])
            let voltageHigh = UInt16(data[5])
            let voltageRaw = voltageLow | (voltageHigh << 8)
            let voltage = Double(voltageRaw) / 1000.0
            
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
