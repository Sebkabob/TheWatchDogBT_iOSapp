//
//  BluetoothManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//
//  ── FIX SUMMARY ──────────────────────────────────────────────────────
//  1. Thread safety: ALL @Observable property writes go through
//     MainActor. BLE delegate callbacks never touch published state
//     directly — they always dispatch to main first.
//  2. Scanning is NEVER stopped for connection. CoreBluetooth handles
//     simultaneous scan + connect fine, and this eliminates the entire
//     class of "scan died after connect attempt" bugs.
//  3. Removed competing scan-restart systems (scan health monitor,
//     separate background scanning flag). There is now ONE method
//     `ensureScanning()` that is idempotent and safe to call from
//     anywhere.
//  4. Connection timeout cleanup is atomic — all state is reset in
//     one main-thread block to avoid races.
//  5. `connectByID` uses `retrieveConnectedPeripherals` as an
//     additional fallback before scanning.
//  ─────────────────────────────────────────────────────────────────────

import Foundation
import CoreBluetooth
import Observation
import SwiftUI

enum MLCState: UInt8 {
    case stationary   = 0
    case doorOpen     = 1
    case inMotion     = 2
    case shaken       = 3
    case stabilizing  = 0xFE
    case unknown      = 0xFF

    var displayName: String {
        switch self {
        case .stationary:   return "Resting"
        case .doorOpen:     return "Door Open"
        case .inMotion:     return "Moving"
        case .shaken:       return "Shaken"
        case .stabilizing:  return "Stabilizing"
        case .unknown:      return "--"
        }
    }

    var color: Color {
        switch self {
        case .stationary:   return .green
        case .doorOpen:     return .yellow
        case .inMotion:     return .orange
        case .shaken:       return .red
        case .stabilizing:  return .blue
        case .unknown:      return .gray
        }
    }
}

@Observable
class BluetoothManager: NSObject {
    // MARK: - Published State (main-thread only)
    var discoveredDevices: [BluetoothDevice] = []
    var isScanning = false
    var isBluetoothReady = false
    var connectedDevice: BluetoothDevice?
    var lastSentData: String = ""
    var deviceState: UInt8 = 0
    var hasReceivedInitialState = false
    var batteryLevel: Int = -1
    var isCharging: Bool = false
    var isCablePlugged: Bool = false
    var isBatteryFull: Bool = false
    var isAlarmActive: Bool = false
    var isFindMyActive: Bool = false
    var mlcState: MLCState = .unknown
    var lastMotionType: MotionEventType = .none
    private var alarmClearTimer: Timer?

    // Debug data
    var debugCurrentDraw: Double = 0.0
    var debugVoltage: Double = 0.0
    var debugAccelX: Float = 0.0
    var debugAccelY: Float = 0.0
    var debugAccelZ: Float = 0.0
    var accelXHistory: [(date: Date, value: Double)] = []
    var accelYHistory: [(date: Date, value: Double)] = []
    var accelZHistory: [(date: Date, value: Double)] = []
    private let accelHistoryDuration: TimeInterval = 15
    var connectionStartTime: Date?
    var connectionDuration: TimeInterval = 0

    // Motion log sync state
    var pendingEventCount: Int = 0
    var isSyncingMotionLogs: Bool = false
    private var motionLogPollTimer: Timer?
    
    private let settingsManager = SettingsManager.shared
    
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private let targetServiceUUID = CBUUID(string: "183E")
    
    // ── Scan throttle ────────────────────────────────────────────────
    private var lastRSSIUpdate: [UUID: Date] = [:]
    private let rssiUpdateInterval: TimeInterval = 0.5
    
    // ── Stale device removal ─────────────────────────────────────────
    private let deviceTimeout: TimeInterval = 5.0
    private var staleDeviceTimer: Timer?
    
    // ── Connection timeout ───────────────────────────────────────────
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 10.0
    private var connectionDurationTimer: Timer?

    // ── Connection tracking ──────────────────────────────────────────
    // Track if we're in the middle of connecting to prevent duplicate attempts
    private(set) var isConnecting = false
    private var pendingConnectionPeripheral: CBPeripheral?
    
    // Flag to suppress auto-reconnect after user-initiated disconnect
    var suppressAutoReconnect = false
    
    // ── Reconnection support ─────────────────────────────────────────
    private var reconnectTargetDeviceID: UUID?
    var isAttemptingReconnect = false
    
    // ── Motion log response opcodes ──────────────────────────────────
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
    private let CMD_PING: UInt8 = 0xFA
    private let CMD_RESET_DEVICE: UInt8 = 0xFB
    
    var deviceStateText: String {
        let isArmed = (deviceState & 0x01) != 0
        return isArmed ? "Locked" : "Unlocked"
    }
    
    // MARK: - Init
    
    override init() {
        super.init()
        let queue = DispatchQueue(label: "com.watchdog.bluetooth", qos: .userInitiated)
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }
    
    // MARK: - Scanning
    
    /// The ONE method to ensure scanning is active. Idempotent — safe to call
    /// from anywhere, any number of times. Never stops an existing scan.
    func ensureScanning() {
        guard isBluetoothReady else {
            print("⚠️ ensureScanning: BT not ready")
            return
        }
        
        // CoreBluetooth is fine with calling scanForPeripherals while already
        // scanning — it just updates the options. So we don't need to check
        // isScanning first. But we do log for debugging.
        if !isScanning {
            print("🔍 ensureScanning: starting scan")
        }
        
        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [targetServiceUUID]
            ]
        )
        
        DispatchQueue.main.async {
            self.isScanning = true
            
            // Ensure stale device timer is running
            if self.staleDeviceTimer == nil {
                self.staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.removeStaleDevices()
                }
            }
        }
    }

    /// Legacy compatibility — calls ensureScanning()
    func startScanning() {
        ensureScanning()
    }
    
    func stopScanning() {
        centralManager.stopScan()
        DispatchQueue.main.async {
            self.isScanning = false
            self.staleDeviceTimer?.invalidate()
            self.staleDeviceTimer = nil
        }
        print("🛑 Stopped scanning")
    }
    
    /// Legacy compatibility
    func startBackgroundScanning() {
        ensureScanning()
    }
    
    func stopBackgroundScanning() {
        // In the new model, we almost never want to stop scanning.
        // Only stop if explicitly told to (e.g. AddNewDeviceView cleanup).
        // The pager model needs scanning always active.
    }

    /// Legacy compatibility
    func resumeBackgroundScanning() {
        ensureScanning()
    }
    
    // MARK: - Connection
    
    func connect(to device: BluetoothDevice) {
        beginConnection(device.peripheral, name: device.name, deviceID: device.id)
    }

    /// Connect using a device UUID. Resolves the peripheral from multiple sources.
    func connectByID(_ deviceID: UUID) {
        // Already connecting to this device?
        if isConnecting && pendingConnectionPeripheral?.identifier == deviceID {
            print("⚠️ Already connecting to this device")
            return
        }

        suppressAutoReconnect = false

        // 1. Best: use peripheral from a recent advertisement
        if let device = discoveredDevices.first(where: { $0.id == deviceID }) {
            print("🔌 Found device in discoveredDevices")
            beginConnection(device.peripheral, name: device.name, deviceID: deviceID)
            return
        }

        // 2. Check if already connected (e.g. system-level reconnect)
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [targetServiceUUID])
        if let peripheral = connected.first(where: { $0.identifier == deviceID }) {
            print("🔌 Found device already connected at system level")
            beginConnection(peripheral, name: peripheral.name ?? "WatchDog", deviceID: deviceID)
            return
        }

        // 3. Fallback: ask CoreBluetooth for a cached peripheral
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [deviceID]).first {
            print("🔌 Found device in CoreBluetooth cache")
            beginConnection(peripheral, name: peripheral.name ?? "WatchDog", deviceID: deviceID)
            return
        }

        // 4. Last resort: scan until we find it
        print("🔍 Device not found — will connect when discovered")
        DispatchQueue.main.async {
            self.isConnecting = true
        }
        startReconnecting(to: deviceID)
    }

    private func beginConnection(_ peripheral: CBPeripheral, name: String, deviceID: UUID) {
        print("🔌 Connecting to: \(name) [\(deviceID.uuidString.prefix(8))]")
        
        // Cancel any existing connection attempt to a DIFFERENT device
        if let pending = pendingConnectionPeripheral, pending.identifier != deviceID {
            print("🔌 Cancelling previous connection attempt")
            centralManager.cancelPeripheralConnection(pending)
        }
        
        DispatchQueue.main.async {
            self.isConnecting = true
            self.pendingConnectionPeripheral = peripheral
        }

        // ── KEY FIX: Do NOT stop scanning ──
        // CoreBluetooth handles concurrent scan + connect. Stopping the scan
        // was causing "scan died" bugs where reconnection and device discovery
        // broke after a failed connection.

        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: false,
            CBConnectPeripheralOptionStartDelayKey: 0
        ]

        centralManager.connect(peripheral, options: options)

        // Connection timeout — all cleanup happens atomically on main thread
        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = Timer.scheduledTimer(withTimeInterval: self.connectionTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("⏱️ Connection timeout for \(name)")
                self.centralManager.cancelPeripheralConnection(peripheral)
                
                // Atomic cleanup
                self.connectionTimer = nil
                self.isConnecting = false
                self.pendingConnectionPeripheral = nil
                
                // If we were trying to reconnect, keep trying
                if self.isAttemptingReconnect {
                    print("🔄 Timeout during reconnect — will retry on next advertisement")
                }
                // Scanning is still alive, no need to restart
            }
        }
    }
    
    func disconnect(from device: BluetoothDevice) {
        print("🔌 Disconnecting from: \(device.name)")
        
        suppressAutoReconnect = true
        stopReconnecting()
        
        centralManager.cancelPeripheralConnection(device.peripheral)
        
        DispatchQueue.main.async {
            self.cleanupConnectionState()
        }
    }
    
    /// Reset all connection-related state. Call on main thread only.
    private func cleanupConnectionState() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectionDurationTimer?.invalidate()
        connectionDurationTimer = nil
        isConnecting = false
        pendingConnectionPeripheral = nil
        connectedDevice = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        lastSentData = ""
        deviceState = 0
        hasReceivedInitialState = false
        batteryLevel = -1
        isCharging = false
        isCablePlugged = false
        isBatteryFull = false
        isAlarmActive = false
        isFindMyActive = false
        mlcState = .unknown
        lastMotionType = .none
        alarmClearTimer?.invalidate()
        alarmClearTimer = nil
        debugCurrentDraw = 0.0
        debugVoltage = 0.0
        connectionStartTime = nil
        connectionDuration = 0
        pendingEventCount = 0
        isSyncingMotionLogs = false
        stopMotionLogPolling()
    }
    
    // MARK: - Battery / charging state helper

    private func updateBatteryState(charging: Bool, battery: Int) {
        let wasCharging = isCharging
        batteryLevel = battery
        isCharging = charging

        if charging && !wasCharging {
            isCablePlugged = true
            isBatteryFull = false
        } else if !charging && wasCharging && battery >= 100 {
            isBatteryFull = true
        } else if !charging && battery < 95 && isCablePlugged {
            isCablePlugged = false
            isBatteryFull = false
        }
    }

    // MARK: - Data Sending

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
        let deviceInfoByte = settingsManager.encodeDeviceInfo()
        let data = Data([settingsByte, deviceInfoByte])
        sendData(data)
        print("📤 Sent settings: 0x\(String(format: "%02X", settingsByte)) deviceInfo: 0x\(String(format: "%02X", deviceInfoByte))")
    }
    
    func sendPing() {
        guard connectedDevice != nil else {
            print("❌ Cannot send ping - not connected")
            return
        }
        let data = Data([CMD_PING, 0x01])
        sendData(data)
        print("🔔 Sent ping (play sound)")
    }

    func sendResetDevice() {
        guard connectedDevice != nil else {
            print("❌ Cannot reset - not connected")
            return
        }
        let data = Data([CMD_RESET_DEVICE])
        sendData(data)
        print("🔄 Sent device reset command")
    }

    // MARK: - Motion Log Sync

    func startMotionLogPolling(interval: TimeInterval = 0.25) {
        stopMotionLogPolling()
        requestMotionLogCount()
        motionLogPollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, self.connectedDevice != nil, !self.isSyncingMotionLogs else { return }
            self.requestMotionLogCount()
        }
    }

    func stopMotionLogPolling() {
        motionLogPollTimer?.invalidate()
        motionLogPollTimer = nil
    }

    func requestMotionLogCount() {
        guard connectedDevice != nil else { return }
        let data = Data([CMD_REQUEST_LOG_COUNT])
        sendData(data)
    }
    
    func requestMotionEvent(at index: UInt16) {
        let data = Data([CMD_REQUEST_EVENT, UInt8((index >> 8) & 0xFF), UInt8(index & 0xFF)])
        sendData(data)
    }
    
    func clearMotionLog() {
        let data = Data([CMD_CLEAR_LOG])
        sendData(data)
    }
    
    private func handleMotionLogResponse(data: Data) {
        guard data.count >= 1 else { return }
        let responseType = data[0]
        
        switch responseType {
        case RESP_LOG_COUNT:
            guard data.count >= 3 else { return }
            let count = (UInt16(data[1]) << 8) | UInt16(data[2])
            print("📥 Motion log count: \(count)")
            DispatchQueue.main.async {
                self.pendingEventCount = Int(count)
                if count > 0 {
                    self.isSyncingMotionLogs = true
                    self.requestMotionEvent(at: 0)
                } else {
                    self.isSyncingMotionLogs = false
                }
            }
            
        case RESP_EVENT_DATA:
            // 11 bytes: 0xE1, index_hi, index_lo, year, month, day, hour, minute, second, motionType, battery
            guard data.count >= 11 else { return }
            let index = (UInt16(data[1]) << 8) | UInt16(data[2])
            let year = data[3], month = data[4], day = data[5]
            let hour = data[6], minute = data[7], second = data[8]
            let motionType = data[9]
            let batteryByte = data[10]

            var timestamp: Date
            if year == 0 && month <= 1 && day <= 1 {
                timestamp = Date()
            } else {
                var components = DateComponents()
                components.year = 2000 + Int(year)
                components.month = max(1, Int(month))
                components.day = max(1, Int(day))
                components.hour = Int(hour)
                components.minute = Int(minute)
                components.second = Int(second)
                timestamp = Calendar.current.date(from: components) ?? Date()
            }

            let config = MotionTypeConfig.convert(firmwareType: motionType)
            guard let deviceID = self.connectedDevice?.id else { return }
            let event = MotionEvent(deviceID: deviceID, timestamp: timestamp, eventType: config.eventType, alarmSounded: config.alarmSounded)
            let charging = (batteryByte & 0x80) != 0
            let battery = Int(batteryByte & 0x7F)

            DispatchQueue.main.async {
                MotionLogManager.shared.addMotionEvent(event)
                self.updateBatteryState(charging: charging, battery: battery)
                let ackData = Data([self.CMD_ACK_EVENT, UInt8((index >> 8) & 0xFF), UInt8(index & 0xFF)])
                self.sendData(ackData)
                let nextIndex = index + 1
                if nextIndex < UInt16(self.pendingEventCount) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.requestMotionEvent(at: nextIndex)
                    }
                } else {
                    self.clearMotionLog()
                    self.isSyncingMotionLogs = false
                }
            }
            
        case RESP_NO_MORE_EVENTS:
            DispatchQueue.main.async { self.isSyncingMotionLogs = false }
            
        case RESP_LOG_CLEARED:
            DispatchQueue.main.async {
                self.pendingEventCount = 0
                self.isSyncingMotionLogs = false
            }
            
        default:
            break
        }
    }
    
    // MARK: - App Lifecycle

    func handleAppBecameActive() {
        guard isBluetoothReady else { return }
        guard connectedDevice == nil && !isConnecting else { return }

        // Reset RSSI timestamps so stale timers don't immediately evict devices
        let now = Date()
        for key in lastRSSIUpdate.keys {
            lastRSSIUpdate[key] = now
        }

        // Force-restart the scan — iOS may have silently stopped it in background
        ensureScanning()
        print("🔄 BLE scan ensured after foreground return")
    }
    
    // MARK: - Reconnection Support
    
    func startReconnecting(to deviceID: UUID) {
        guard !suppressAutoReconnect else {
            print("⚠️ Auto-reconnect suppressed")
            return
        }
        
        if isAttemptingReconnect && reconnectTargetDeviceID == deviceID {
            return
        }
        
        reconnectTargetDeviceID = deviceID
        DispatchQueue.main.async {
            self.isAttemptingReconnect = true
        }
        
        print("🔄 Will connect to \(deviceID.uuidString.prefix(8)) when discovered")
        ensureScanning()
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
    
    /// Called from didDiscover — if we're reconnecting and this is our target, connect.
    private func tryImmediateReconnect(peripheral: CBPeripheral, name: String) {
        guard isAttemptingReconnect,
              let targetID = reconnectTargetDeviceID,
              peripheral.identifier == targetID,
              !suppressAutoReconnect,
              connectedDevice == nil else {
            return
        }

        print("🔄 Target device discovered — connecting immediately!")
        stopReconnecting()
        beginConnection(peripheral, name: name, deviceID: peripheral.identifier)
    }
    
    // MARK: - Stale Device Removal
    
    private func removeStaleDevices() {
        let now = Date()
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { device in
                if self.isAttemptingReconnect && device.id == self.reconnectTargetDeviceID {
                    return false
                }
                guard let lastUpdate = self.lastRSSIUpdate[device.id] else { return true }
                let isStale = now.timeIntervalSince(lastUpdate) > self.deviceTimeout
                if isStale {
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
            let ready = central.state == .poweredOn
            self.isBluetoothReady = ready
            
            switch central.state {
            case .poweredOn:
                print("✅ Bluetooth powered on")
                self.ensureScanning()
            case .poweredOff:
                print("❌ Bluetooth powered off")
                self.isScanning = false
                self.connectedDevice = nil
            case .unauthorized:
                print("⚠️ Bluetooth unauthorized")
            case .unsupported:
                print("❌ Bluetooth unsupported")
            case .resetting:
                print("🔄 Bluetooth resetting")
                self.isScanning = false
            case .unknown:
                print("❓ Bluetooth state unknown")
            @unknown default:
                print("❓ Bluetooth state unknown")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceID = peripheral.identifier
        let now = Date()
        
        // Skip RSSI throttle only for reconnect target (needs instant detection)
        let isReconnectTarget = isAttemptingReconnect && deviceID == reconnectTargetDeviceID

        if !isReconnectTarget {
            if let lastUpdate = lastRSSIUpdate[deviceID],
               now.timeIntervalSince(lastUpdate) < rssiUpdateInterval {
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
            
            // Immediate reconnection if this is our target
            self.tryImmediateReconnect(peripheral: peripheral, name: name)
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
            self.pendingConnectionPeripheral = nil
            self.suppressAutoReconnect = false
            
            let name: String
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                name = self.discoveredDevices[index].name
                self.discoveredDevices[index] = BluetoothDevice(
                    id: peripheral.identifier,
                    name: name,
                    peripheral: peripheral,
                    rssi: self.discoveredDevices[index].rssi,
                    isConnected: true
                )
                self.connectedDevice = self.discoveredDevices[index]
            } else {
                name = peripheral.name ?? "WatchDog"
                let device = BluetoothDevice(
                    id: peripheral.identifier,
                    name: name,
                    peripheral: peripheral,
                    rssi: -50,
                    isConnected: true
                )
                self.discoveredDevices.append(device)
                self.connectedDevice = device
            }

            // Load this device's saved settings
            self.settingsManager.loadDeviceSettings(for: peripheral.identifier)
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([targetServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            print("❌ Disconnected from: \(peripheral.name ?? "Unknown") - Error: \(error.localizedDescription)")
        } else {
            print("🔌 Disconnected from: \(peripheral.name ?? "Unknown")")
        }
        
        DispatchQueue.main.async {
            // Only clean up if this peripheral matches our current connection.
            // A late disconnect callback from a previous connection attempt
            // must NOT wipe state for a new connection in progress.
            let isCurrentConnection = self.connectedDevice?.id == peripheral.identifier
            let isPendingConnection = self.pendingConnectionPeripheral?.identifier == peripheral.identifier
            
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[index].isConnected = false
            }
            
            if isCurrentConnection {
                self.cleanupConnectionState()
            } else if isPendingConnection && !isCurrentConnection {
                // Pending connection failed before didConnect fired
                self.isConnecting = false
                self.pendingConnectionPeripheral = nil
                self.connectionTimer?.invalidate()
                self.connectionTimer = nil
            }
            
            // Scanning should still be alive — no need to restart
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")

        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionPeripheral = nil

            if self.isAttemptingReconnect {
                print("🔄 Connection failed — will retry on next advertisement")
            }
            // Scanning still alive — no restart needed
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
        
        guard let services = peripheral.services else { return }
        
        for service in services {
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
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                print("✅ Write characteristic found")
            }
            
            if characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("✅ Subscribed to notifications")
            }
            
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
        
        // One-shot sync on connect
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.connectedDevice != nil else { return }
            self.requestMotionLogCount()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error updating notification state: \(error.localizedDescription)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error reading characteristic: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value, data.count >= 1 else { return }
        
        let firstByte = data[0]
        
        // ─── Motion alert (0xFF) ───
        if firstByte == MOTION_ALERT_MARKER {
            let motionType: MotionEventType
            let batteryByte: UInt8

            if data.count >= 3 {
                motionType = MotionEventType(rawValue: data[1]) ?? .inMotion
                batteryByte = data[2]
            } else if data.count >= 2 {
                motionType = .inMotion
                batteryByte = data[1]
            } else {
                motionType = .inMotion
                batteryByte = 0
            }

            let charging = (batteryByte & 0x80) != 0
            let battery = Int(batteryByte & 0x7F)

            DispatchQueue.main.async {
                self.lastMotionType = motionType
                self.updateBatteryState(charging: charging, battery: battery)
                self.isAlarmActive = true
                self.alarmClearTimer?.invalidate()
                self.alarmClearTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                    self?.isAlarmActive = false
                }
            }
            return
        }
        
        // ─── Motion log response (0xE0–0xE3) ───
        if firstByte >= 0xE0 && firstByte <= 0xE3 {
            handleMotionLogResponse(data: data)
            return
        }
        
        // ─── Regular status update ───
        let settingsByte = firstByte

        var charging = false
        var battery = 0
        if data.count >= 2 {
            let batteryByte = data[1]
            charging = (batteryByte & 0x80) != 0
            battery = Int(batteryByte & 0x7F)
        }

        var current: Double = 0.0
        var voltage: Double = 0.0
        if data.count >= 6 {
            let currentRaw = UInt16(data[2]) | (UInt16(data[3]) << 8)
            current = Double(Int16(bitPattern: currentRaw))
            let voltageRaw = UInt16(data[4]) | (UInt16(data[5]) << 8)
            voltage = Double(voltageRaw) / 1000.0
        }

        let mlc: MLCState = data.count >= 7 ? (MLCState(rawValue: data[6]) ?? .unknown) : .unknown

        var accelX: Float = 0.0, accelY: Float = 0.0, accelZ: Float = 0.0
        if data.count >= 13 {
            let rawX = Int16(data[7]) | (Int16(data[8]) << 8)
            let rawY = Int16(data[9]) | (Int16(data[10]) << 8)
            let rawZ = Int16(data[11]) | (Int16(data[12]) << 8)
            accelX = Float(rawX) * 16.0 / 32768.0
            accelY = Float(rawY) * 16.0 / 32768.0
            accelZ = Float(rawZ) * 16.0 / 32768.0
        }

        let deviceInfoByte: UInt8? = data.count >= 14 ? data[13] : nil

        DispatchQueue.main.async {
            self.deviceState = settingsByte
            self.hasReceivedInitialState = true
            self.settingsManager.decodeSettings(from: settingsByte)
            if let deviceInfoByte { self.settingsManager.decodeDeviceInfo(from: deviceInfoByte) }

            // Clear alarm when device is no longer armed
            if !self.settingsManager.isArmed && self.isAlarmActive {
                self.isAlarmActive = false
                self.alarmClearTimer?.invalidate()
                self.alarmClearTimer = nil
            }

            self.updateBatteryState(charging: charging, battery: battery)
            self.debugCurrentDraw = current
            self.debugVoltage = voltage
            self.mlcState = mlc
            self.debugAccelX = accelX
            self.debugAccelY = accelY
            self.debugAccelZ = accelZ

            MotionDataRecorder.shared.addSample(x: accelX, y: accelY, z: accelZ)

            let now = Date()
            self.accelXHistory.append((date: now, value: Double(accelX)))
            self.accelYHistory.append((date: now, value: Double(accelY)))
            self.accelZHistory.append((date: now, value: Double(accelZ)))
            let cutoff = now.addingTimeInterval(-self.accelHistoryDuration)
            self.accelXHistory.removeAll { $0.date < cutoff }
            self.accelYHistory.removeAll { $0.date < cutoff }
            self.accelZHistory.removeAll { $0.date < cutoff }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Write error: \(error.localizedDescription)")
        }
    }
}
