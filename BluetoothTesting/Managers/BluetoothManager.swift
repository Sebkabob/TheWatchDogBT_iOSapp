//
//  BluetoothManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

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
    var discoveredDevices: [BluetoothDevice] = []
    var isScanning = false
    var isBluetoothReady = false
    var connectedDevice: BluetoothDevice?
    var lastSentData: String = ""
    var deviceState: UInt8 = 0
    var hasReceivedInitialState = false
    var batteryLevel: Int = -1
    var isCharging: Bool = false
    var isCablePlugged: Bool = false    // true once charging starts; cleared when discharging
    var isBatteryFull: Bool = false     // true when charging ends at 100 %
    var isAlarmActive: Bool = false     // set on 0xFF motion alert; auto-clears after ~30 s
    var isFindMyActive: Bool = false    // set by Find My command reply
    var mlcState: MLCState = .unknown   // real-time MLC motion classification from status notifications
    var lastMotionType: MotionEventType = .none  // motion type from most recent motion alert
    private var alarmClearTimer: Timer?

    // Debug data
    var debugCurrentDraw: Double = 0.0  // mA
    var debugVoltage: Double = 0.0      // V
    var debugAccelX: Float = 0.0        // g
    var debugAccelY: Float = 0.0        // g
    var debugAccelZ: Float = 0.0        // g
    var accelXHistory: [(date: Date, value: Double)] = []
    var accelYHistory: [(date: Date, value: Double)] = []
    var accelZHistory: [(date: Date, value: Double)] = []
    private let accelHistoryDuration: TimeInterval = 15
    var connectionStartTime: Date?
    var connectionDuration: TimeInterval = 0

    // Motion log sync state
    var pendingEventCount: Int = 0
    var isSyncingMotionLogs: Bool = false
    
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
    var isAttemptingReconnect = false
    
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

    // Ping command opcode
    private let CMD_PING: UInt8 = 0xFA
    
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
        beginConnection(device.peripheral, name: device.name, deviceID: device.id)
    }

    /// Connect using a device UUID. Resolves the peripheral from discoveredDevices
    /// first (fresh from recent advertisement), then CoreBluetooth's cache, then
    /// falls back to scanning until the device is found.
    func connectByID(_ deviceID: UUID) {
        if isConnecting && pendingConnectionDevice == deviceID {
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

        // 2. Fallback: ask CoreBluetooth for a cached peripheral
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [deviceID]).first {
            print("🔌 Found device in CoreBluetooth cache")
            beginConnection(peripheral, name: peripheral.name ?? "WatchDog", deviceID: deviceID)
            return
        }

        // 3. Last resort: scan until we find it, then auto-connect
        print("🔍 Device not found yet — scanning to reconnect...")
        isConnecting = true
        pendingConnectionDevice = deviceID
        startReconnecting(to: deviceID)
    }

    private func beginConnection(_ peripheral: CBPeripheral, name: String, deviceID: UUID) {
        isConnecting = true
        pendingConnectionDevice = deviceID

        print("🔌 Connecting to: \(name) [\(deviceID.uuidString.prefix(8))]")

        // Stop scanning to let CoreBluetooth focus on the connection
        if isScanning {
            centralManager.stopScan()
            DispatchQueue.main.async {
                self.isScanning = false
            }
        }

        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: false,
            CBConnectPeripheralOptionStartDelayKey: 0
        ]

        centralManager.connect(peripheral, options: options)

        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = Timer.scheduledTimer(withTimeInterval: self.connectionTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("⏱️ Connection timeout for \(name)")
                self.centralManager.cancelPeripheralConnection(peripheral)
                self.connectionTimer = nil
                self.isConnecting = false
                self.pendingConnectionDevice = nil
                // Always restart scanning after timeout
                self.resumeBackgroundScanning()
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
            self.isCablePlugged = false
            self.isBatteryFull = false
            self.isAlarmActive = false
            self.isFindMyActive = false
            self.alarmClearTimer?.invalidate()
            self.alarmClearTimer = nil
            self.debugCurrentDraw = 0.0
            self.debugVoltage = 0.0
            self.connectionStartTime = nil
            self.connectionDuration = 0
            self.pendingEventCount = 0
            self.isSyncingMotionLogs = false
        }
    }
    
    // MARK: - Battery / charging state helper (call on main thread)

    /// Updates battery-related LED state properties from each incoming battery byte.
    /// Infers isCablePlugged from charging transitions since the protocol has no explicit cable bit.
    private func updateBatteryState(charging: Bool, battery: Int) {
        let wasCharging = isCharging
        batteryLevel = battery
        isCharging = charging

        if charging && !wasCharging {
            // Cable just plugged in and started charging
            isCablePlugged = true
            isBatteryFull = false
        } else if !charging && wasCharging && battery >= 100 {
            // Charging finished — cable still plugged, battery full
            isBatteryFull = true
            // isCablePlugged stays true
        } else if !charging && battery < 95 && isCablePlugged {
            // Battery is draining → cable has been removed
            isCablePlugged = false
            isBatteryFull = false
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
        let deviceInfoByte = settingsManager.encodeDeviceInfo()
        let data = Data([settingsByte, deviceInfoByte])
        sendData(data)
        print("📤 Sent settings: 0x\(String(format: "%02X", settingsByte)) deviceInfo: 0x\(String(format: "%02X", deviceInfoByte))")
    }
    
    // MARK: - Ping / Find Device

    func sendPing() {
        guard connectedDevice != nil else {
            print("❌ Cannot send ping - not connected")
            return
        }
        let data = Data([CMD_PING, 0x01]) // bit 0 = play sound
        sendData(data)
        print("🔔 Sent ping (play sound)")
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

    /// Resume background scanning without clearing discoveredDevices.
    /// Use this when scanning died (e.g. after connect() stopped it) but we
    /// need to preserve the existing device list for UI and reconnection.
    func resumeBackgroundScanning() {
        guard isBluetoothReady else {
            shouldStartScanningWhenReady = true
            return
        }

        // Don't restart scanning during an active connection — it's not needed
        // and can interfere with CoreBluetooth's connection flow
        guard connectedDevice == nil && !isConnecting else { return }

        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [targetServiceUUID]
            ]
        )

        isScanning = true
        isBackgroundScanning = true
        lastAdvertisementReceived = Date()

        startScanHealthMonitor()

        // Restart stale device timer if not running
        if staleDeviceTimer == nil {
            DispatchQueue.main.async {
                self.staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.removeStaleDevices()
                }
            }
        }

        print("🔍 Resumed background scanning (devices preserved)")
    }

    // MARK: - App Lifecycle

    /// Called when the app returns to the foreground. Force-restarts the BLE scan
    /// because iOS suspends scanning in the background and it may not resume reliably.
    func handleAppBecameActive() {
        guard isBluetoothReady else {
            shouldStartScanningWhenReady = true
            return
        }

        // Don't interfere with an active connection attempt
        guard connectedDevice == nil && !isConnecting else {
            print("🔄 App became active but connection in progress — skipping scan restart")
            return
        }

        // Reset timestamps so stale timers don't immediately remove devices
        // that were seen before backgrounding
        lastAdvertisementReceived = Date()
        let now = Date()
        for key in lastRSSIUpdate.keys {
            lastRSSIUpdate[key] = now
        }

        // Force-restart the scan — iOS may have silently stopped it
        centralManager.stopScan()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.isBluetoothReady else { return }
            // Re-check connection state after the delay
            guard self.connectedDevice == nil && !self.isConnecting else { return }

            self.centralManager.scanForPeripherals(
                withServices: [self.targetServiceUUID],
                options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true,
                    CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [self.targetServiceUUID]
                ]
            )

            self.isScanning = true
            self.isBackgroundScanning = true
            self.lastAdvertisementReceived = Date()
            print("🔄 BLE scan force-restarted after foreground return")
        }
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
              connectedDevice == nil else {
            return
        }

        print("🔄 Target device discovered during reconnect — connecting immediately!")
        // Use beginConnection directly with the fresh peripheral from didDiscover.
        // This bypasses the isConnecting guard since WE are the pending connection.
        stopReconnecting()
        beginConnection(device.peripheral, name: device.name, deviceID: device.id)
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
                // Always start scanning as soon as BLE is ready — no need to wait
                // for a UI trigger. This eliminates cold-start delays.
                self.shouldStartScanningWhenReady = false
                if !self.isScanning {
                    self.resumeBackgroundScanning()
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

        print("🔍 Discovering services...")
        peripheral.discoverServices([targetServiceUUID])
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
            self.isCablePlugged = false
            self.isBatteryFull = false
            self.isAlarmActive = false
            self.isFindMyActive = false
            self.mlcState = .unknown
            self.lastMotionType = .none
            self.alarmClearTimer?.invalidate()
            self.alarmClearTimer = nil
            self.debugCurrentDraw = 0.0
            self.debugVoltage = 0.0
            self.connectionStartTime = nil
            self.connectionDuration = 0
            self.pendingEventCount = 0
            self.isSyncingMotionLogs = false

            self.connectionDurationTimer?.invalidate()
            self.connectionDurationTimer = nil

            // Only clear connection state if we're NOT already in a new
            // connection attempt — otherwise this late callback from a prior
            // disconnect will sabotage the new connect().
            if !self.isConnecting {
                self.pendingConnectionDevice = nil

                // Restart scanning so bonded device "in range" state updates properly
                if !self.isScanning && self.isBluetoothReady {
                    self.resumeBackgroundScanning()
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")

        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionDevice = nil

            // Restart scanning so the app isn't stuck
            if !self.isScanning && self.isBluetoothReady {
                self.resumeBackgroundScanning()
            }

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
        
        // After characteristics are discovered, trigger motion log sync after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
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
            let motionType: MotionEventType
            let batteryByte: UInt8

            if data.count >= 3 {
                // New 3-byte format: [0xFF] [motionType] [battery]
                motionType = MotionEventType(rawValue: data[1]) ?? .inMotion
                batteryByte = data[2]
            } else if data.count >= 2 {
                // Legacy 2-byte format: [0xFF] [battery]
                motionType = .inMotion
                batteryByte = data[1]
            } else {
                motionType = .inMotion
                batteryByte = 0
            }

            let charging = (batteryByte & 0x80) != 0
            let battery = Int(batteryByte & 0x7F)
            print("🚨 Motion alert: \(motionType.displayName)")

            DispatchQueue.main.async {
                self.lastMotionType = motionType
                self.updateBatteryState(charging: charging, battery: battery)
                // Mark alarm active; auto-clear after ~30 s (full melody duration)
                self.isAlarmActive = true
                self.alarmClearTimer?.invalidate()
                self.alarmClearTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                    self?.isAlarmActive = false
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
        // Parse all fields on the BLE callback thread, then apply atomically on main.
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

        var accelX: Float = 0.0
        var accelY: Float = 0.0
        var accelZ: Float = 0.0
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
            let oldState = self.deviceState
            self.deviceState = settingsByte
            self.hasReceivedInitialState = true
            self.settingsManager.decodeSettings(from: settingsByte)
            if let deviceInfoByte {
                self.settingsManager.decodeDeviceInfo(from: deviceInfoByte)
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

            print("📥 State: 0x\(String(format: "%02X", settingsByte)) (was: 0x\(String(format: "%02X", oldState))), 🔋 \(battery)%\(charging ? " ⚡" : ""), MLC: \(mlc.displayName)")
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
