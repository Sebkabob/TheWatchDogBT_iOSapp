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

enum UnpairError: LocalizedError {
    case notConnected
    case ackTimeout

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WatchDog is not connected."
        case .ackTimeout:   return "WatchDog did not confirm unpair within 2 seconds."
        }
    }
}

enum DiagnosticError: LocalizedError {
    case notConnected
    case timeout
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:      return "WatchDog is not connected."
        case .timeout:           return "No response from device."
        case .malformedResponse: return "Malformed diagnostic response."
        }
    }
}

struct WatchDogFirmware: Equatable {
    let major: UInt8
    let main: UInt8
    let v2: UInt8

    var displayString: String {
        String(format: "Firmware V%d.%d.%02d", major, main, v2)
    }

    /// True when this firmware is at least `(major, main, v2)`.
    func isAtLeast(_ major: UInt8, _ main: UInt8, _ v2: UInt8) -> Bool {
        if self.major != major { return self.major > major }
        if self.main != main { return self.main > main }
        return self.v2 >= v2
    }
}

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
    var watchDogIdentifiers: [UUID: UInt16] = [:]
    var watchDogFirmwares: [UUID: WatchDogFirmware] = [:]
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
    /// Per-event watchdog. Armed when a CMD_REQUEST_EVENT is sent, cleared
    /// on RESP_EVENT_DATA / RESP_NO_MORE_EVENTS / disconnect. If it fires,
    /// the sync is force-ended so the user isn't stuck on a half-drained
    /// view because one notification quietly disappeared.
    private var eventFetchWatchdog: Timer?
    private let eventFetchTimeoutSeconds: TimeInterval = 2.0
    
    private let settingsManager = SettingsManager.shared
    
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private let targetServiceUUID = CBUUID(string: "183E")
    private let batteryDiagCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000004442")
    
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
    private let RESP_UNPAIR_ACK: UInt8      = 0xE4
    private let MOTION_ALERT_MARKER: UInt8  = 0xFF

    // Motion log command opcodes
    private let CMD_REQUEST_LOG_COUNT: UInt8 = 0xF0
    private let CMD_REQUEST_EVENT: UInt8     = 0xF1
    private let CMD_CLEAR_LOG: UInt8         = 0xF2
    private let CMD_ACK_EVENT: UInt8         = 0xF3
    private let CMD_PING: UInt8 = 0xFA
    private let CMD_RESET_DEVICE: UInt8 = 0xFB
    /// New TLV diagnostic request — replaces the legacy 0xFE/0xE5 single-snapshot path.
    /// Payload: `[0xF4, section_mask]` (after the 4-byte loyalty token, prepended by sendData).
    static let CMD_REQUEST_DIAG: UInt8 = 0xF4

    // ── Loyalty token opcodes (iOS → APPTOWD) ─────────────────────────
    private let CMD_UNBOND_DEVICE: UInt8 = 0xC0
    private let CMD_CLAIM_DEVICE:  UInt8 = 0xC1
    private let CMD_VERIFY_OWNER:  UInt8 = 0xC2

    // ── Loyalty token responses (firmware → iOS via DEVICESTATUS) ─────
    private let RESP_CLAIM_OK:  UInt8 = 0xE7
    private let RESP_REJECT:    UInt8 = 0xE8
    private let RESP_VERIFY_OK: UInt8 = 0xE9
    // RESP_UNPAIR_ACK (0xE4) already declared above — reused for UNBOND_OK

    // ── Loyalty handshake state ──────────────────────────────────────
    enum LoyaltyState: Equatable {
        case idle
        case awaitingClaimAck
        case awaitingVerifyAck
        case verified
        case rejected
        case awaitingUnbondAck
    }

    var loyaltyState: LoyaltyState = .idle
    var notYourDeviceAlert: String?

    private var loyaltyTimer: Timer?
    private let loyaltyTimeout: TimeInterval = 1.5

    // ── Unpair flow state ────────────────────────────────────────────
    private var unpairCompletion: ((Result<Void, Error>) -> Void)?
    private var unpairTimer: Timer?
    private var pendingUnpairDeviceID: UUID?
    private let unpairAckTimeout: TimeInterval = 2.0

    // ── Diagnostic flow state ────────────────────────────────────────
    private var diagnosticCompletion: ((Result<DiagnosticReport, Error>) -> Void)?
    private var diagnosticTimer: Timer?
    private let diagnosticTimeout: TimeInterval = 2.0
    /// Throttle floor for back-to-back diagnostic requests. Set below the
    /// view's 250 ms poll cadence so polling isn't dropped, but high enough
    /// to coalesce accidental double-taps.
    private let diagnosticMinInterval: TimeInterval = 0.2
    private var lastDiagnosticRequestAt: Date?

    // ── Unpair-while-disconnected state ──────────────────────────────
    // Set by unpairDeviceWhileDisconnected; consumed by didDiscoverCharacteristicsFor
    // *instead of* the normal CLAIM/VERIFY handshake.
    private var pendingUnbondAfterConnect: UUID?
    private var pendingUnbondCompletion:   ((Result<Void, Error>) -> Void)?
    private var unpairConnectTimer:        Timer?
    private let unpairConnectTimeout:      TimeInterval = 8.0

    // ── Demo mode ────────────────────────────────────────────────────
    /// True while a DemoSession is active. Every BLE action (`connect`,
    /// `disconnect`, `sendSettings`, scanning, etc.) is short-circuited so the
    /// demo never touches CoreBluetooth, and a snapshot of the observable
    /// state is restored on exit. Read-only outside the manager — flip it via
    /// `enterDemoMode()` / `exitDemoMode()`.
    private(set) var isDemoMode: Bool = false
    private var demoSnapshot: DemoSnapshot?

    private struct DemoSnapshot {
        var batteryLevel: Int
        var deviceState: UInt8
        var hasReceivedInitialState: Bool
        var isCharging: Bool
        var isCablePlugged: Bool
        var isBatteryFull: Bool
        var isAlarmActive: Bool
        var isFindMyActive: Bool
        var mlcState: MLCState
        var lastMotionType: MotionEventType
        var debugCurrentDraw: Double
        var debugVoltage: Double
        var debugAccelX: Float
        var debugAccelY: Float
        var debugAccelZ: Float
        var suppressAutoReconnect: Bool
    }
    
    var deviceStateText: String {
        let isArmed = (deviceState & 0x01) != 0
        return isArmed ? "Locked" : "Unlocked"
    }

    func deviceLabel(for deviceID: UUID) -> String? {
        guard let id = watchDogIdentifiers[deviceID] else { return nil }
        return String(format: "WatchDog #%04d", id)
    }

    // Falls back when older 16-byte status frames carry no version bytes.
    func firmwareLabel(for deviceID: UUID) -> String {
        watchDogFirmwares[deviceID]?.displayString ?? "Firmware V?.?.??"
    }

    func deviceHeader(for deviceID: UUID) -> String? {
        guard let device = deviceLabel(for: deviceID) else { return nil }
        return "\(device), \(firmwareLabel(for: deviceID))"
    }
    
    // MARK: - Init

    override init() {
        super.init()
        Log.contextProvider = { [weak self] in
            guard let self = self, self.connectedDevice != nil else { return nil }
            let soc = self.batteryLevel >= 0 ? "🔋\(self.batteryLevel)%" : "🔋--"
            let charge = self.isCharging ? " 🔌" : ""
            let lock = (self.deviceState & 0x01) != 0 ? "🔒 Armed" : "🔓 Idle"
            return "\(soc)\(charge) · \(lock)"
        }
        Log.banner()
        let queue = DispatchQueue(label: "com.watchdog.bluetooth", qos: .userInitiated)
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }
    
    // MARK: - Scanning
    
    /// The ONE method to ensure scanning is active. Idempotent — safe to call
    /// from anywhere, any number of times. Never stops an existing scan.
    func ensureScanning() {
        guard !isDemoMode else { return }
        guard isBluetoothReady else {
            Log.warn(.ble, "ensureScanning: BT not ready")
            return
        }

        // CoreBluetooth is fine with calling scanForPeripherals while already
        // scanning — it just updates the options. So we don't need to check
        // isScanning first. But we do log for debugging.
        if !isScanning {
            Log.info(.ble, "Starting scan")
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

    func stopScanning() {
        centralManager.stopScan()
        DispatchQueue.main.async {
            self.isScanning = false
            self.staleDeviceTimer?.invalidate()
            self.staleDeviceTimer = nil
        }
        Log.info(.ble, "Stopped scanning")
    }

    /// Legacy compatibility
    func startBackgroundScanning() {
        ensureScanning()
    }

    // MARK: - Connection
    
    func connect(to device: BluetoothDevice) {
        guard !isDemoMode else { return }
        beginConnection(device.peripheral, name: device.name, deviceID: device.id)
    }

    /// Connect using a device UUID. Resolves the peripheral from multiple sources.
    func connectByID(_ deviceID: UUID) {
        guard !isDemoMode else { return }
        // Already connecting to this device?
        if isConnecting && pendingConnectionPeripheral?.identifier == deviceID {
            Log.warn(.ble, "Already connecting to this device")
            return
        }

        suppressAutoReconnect = false

        // 1. Best: use peripheral from a recent advertisement
        if let device = discoveredDevices.first(where: { $0.id == deviceID }) {
            Log.info(.ble, "Resolved peripheral · advertisement cache")
            beginConnection(device.peripheral, name: device.name, deviceID: deviceID)
            return
        }

        // 2. Check if already connected (e.g. system-level reconnect)
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [targetServiceUUID])
        if let peripheral = connected.first(where: { $0.identifier == deviceID }) {
            Log.info(.ble, "Resolved peripheral · already connected (system)")
            beginConnection(peripheral, name: peripheral.name ?? "WatchDog", deviceID: deviceID)
            return
        }

        // 3. Fallback: ask CoreBluetooth for a cached peripheral
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [deviceID]).first {
            Log.info(.ble, "Resolved peripheral · CoreBluetooth cache")
            beginConnection(peripheral, name: peripheral.name ?? "WatchDog", deviceID: deviceID)
            return
        }

        // 4. Last resort: scan until we find it
        Log.info(.ble, "Peripheral not found — will connect when discovered")
        DispatchQueue.main.async {
            self.isConnecting = true
        }
        startReconnecting(to: deviceID)
    }

    private func beginConnection(_ peripheral: CBPeripheral, name: String, deviceID: UUID) {
        Log.info(.ble, "Connecting to \(name) [\(deviceID.uuidString.prefix(8))]")

        // Cancel any existing connection attempt to a DIFFERENT device
        if let pending = pendingConnectionPeripheral, pending.identifier != deviceID {
            Log.info(.ble, "Cancelling previous connection attempt")
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
                Log.warn(.ble, "Connection timeout · \(name)")
                self.centralManager.cancelPeripheralConnection(peripheral)

                // Atomic cleanup
                self.connectionTimer = nil
                self.isConnecting = false
                self.pendingConnectionPeripheral = nil

                // If we were trying to reconnect, keep trying
                if self.isAttemptingReconnect {
                    Log.info(.ble, "Timeout during reconnect — will retry on next advertisement")
                }
                // Scanning is still alive, no need to restart
            }
        }
    }
    
    func disconnect(from device: BluetoothDevice) {
        guard !isDemoMode else { return }
        Log.info(.ble, "Disconnecting from \(device.name)")

        suppressAutoReconnect = true
        stopReconnecting()

        centralManager.cancelPeripheralConnection(device.peripheral)

        DispatchQueue.main.async {
            self.cleanupConnectionState()
        }
    }

    /// Tear down all live BLE state for a "Wipe App Data" reset. Cancels any
    /// in-flight or active connection, stops scanning, and drops every cached
    /// peripheral so the UI can't keep referencing forgotten devices.
    func wipeAllDeviceState() {
        suppressAutoReconnect = true
        stopReconnecting()
        if let device = connectedDevice {
            centralManager.cancelPeripheralConnection(device.peripheral)
        }
        if let pending = pendingConnectionPeripheral {
            centralManager.cancelPeripheralConnection(pending)
        }
        if isScanning {
            centralManager.stopScan()
            isScanning = false
        }
        cleanupConnectionState()
        discoveredDevices.removeAll()
        watchDogIdentifiers.removeAll()
        watchDogFirmwares.removeAll()
        lastRSSIUpdate.removeAll()
        Log.ok(.ble, "Wiped all BLE state")
    }

    // MARK: - Demo Mode

    /// Disconnects any active peripheral, halts scanning, and overrides the
    /// observable state so the demo always renders as "connected, idle, full
    /// battery" without any BLE traffic. Every BLE method on this manager is
    /// guarded on `isDemoMode` so stray callers can't accidentally talk to a
    /// peripheral while a session is open. The companion call into
    /// `SettingsManager.enterDemoMode(deviceID:)` happens on the caller side
    /// (`MainAppView`) so both flips remain co-located with the rest of the
    /// demo lifecycle.
    func enterDemoMode() {
        guard !isDemoMode else { return }
        demoSnapshot = DemoSnapshot(
            batteryLevel: batteryLevel,
            deviceState: deviceState,
            hasReceivedInitialState: hasReceivedInitialState,
            isCharging: isCharging,
            isCablePlugged: isCablePlugged,
            isBatteryFull: isBatteryFull,
            isAlarmActive: isAlarmActive,
            isFindMyActive: isFindMyActive,
            mlcState: mlcState,
            lastMotionType: lastMotionType,
            debugCurrentDraw: debugCurrentDraw,
            debugVoltage: debugVoltage,
            debugAccelX: debugAccelX,
            debugAccelY: debugAccelY,
            debugAccelZ: debugAccelZ,
            suppressAutoReconnect: suppressAutoReconnect
        )

        if let device = connectedDevice {
            centralManager.cancelPeripheralConnection(device.peripheral)
        }
        if let pending = pendingConnectionPeripheral {
            centralManager.cancelPeripheralConnection(pending)
        }
        if isScanning {
            centralManager.stopScan()
            isScanning = false
            staleDeviceTimer?.invalidate()
            staleDeviceTimer = nil
        }
        cleanupConnectionState()

        suppressAutoReconnect = true
        isDemoMode = true

        batteryLevel = 100
        deviceState = 0
        hasReceivedInitialState = true
        isCharging = false
        isCablePlugged = false
        isBatteryFull = false
        isAlarmActive = false
        isFindMyActive = false
        mlcState = .stationary
        lastMotionType = .none
        debugCurrentDraw = 0
        debugVoltage = 0
        debugAccelX = 0
        debugAccelY = 0
        debugAccelZ = 0
        Log.info(.ble, "Entered demo mode")
    }

    /// Restores the observable state captured at `enterDemoMode()` and resumes
    /// scanning if Bluetooth is ready. Always called in tandem with
    /// `SettingsManager.exitDemoMode()` from `MainAppView`.
    func exitDemoMode() {
        guard isDemoMode else { return }
        isDemoMode = false
        if let snap = demoSnapshot {
            batteryLevel = snap.batteryLevel
            deviceState = snap.deviceState
            hasReceivedInitialState = snap.hasReceivedInitialState
            isCharging = snap.isCharging
            isCablePlugged = snap.isCablePlugged
            isBatteryFull = snap.isBatteryFull
            isAlarmActive = snap.isAlarmActive
            isFindMyActive = snap.isFindMyActive
            mlcState = snap.mlcState
            lastMotionType = snap.lastMotionType
            debugCurrentDraw = snap.debugCurrentDraw
            debugVoltage = snap.debugVoltage
            debugAccelX = snap.debugAccelX
            debugAccelY = snap.debugAccelY
            debugAccelZ = snap.debugAccelZ
            suppressAutoReconnect = snap.suppressAutoReconnect
        }
        demoSnapshot = nil
        Log.info(.ble, "Exited demo mode")
        if isBluetoothReady {
            ensureScanning()
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
        cancelEventFetchWatchdog()
        loyaltyTimer?.invalidate()
        loyaltyTimer = nil
        loyaltyState = .idle
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

    /// Send a regular (non-loyalty) command. Prepends the 4-byte loyalty
    /// token; drops the write if the loyalty handshake hasn't completed.
    /// Loyalty opcodes (CLAIM/VERIFY/UNBOND) bypass this and write directly.
    func sendData(_ data: Data) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedDevice?.peripheral else {
            Log.err(.ble, "No writable characteristic found")
            return
        }
        guard let token = LoyaltyTokenStore.shared.token else {
            Log.err(.ble, "sendData: no loyalty token available")
            return
        }
        guard loyaltyState == .verified else {
            Log.warn(.ble, "sendData dropped · loyalty not verified (state=\(loyaltyState))")
            return
        }

        var prefixed = token
        prefixed.append(data)
        peripheral.writeValue(prefixed, for: characteristic, type: .withResponse)
        Log.tx(.ble, "Sent \(prefixed.count) bytes")
    }

    func sendSettings() {
        guard !isDemoMode else { return }
        let settingsByte      = settingsManager.encodeSettings()
        let deviceInfoByte    = settingsManager.encodeDeviceInfo()
        let alarmDurationByte = settingsManager.encodeAlarmDuration()
        let ledBrightnessByte = settingsManager.encodeLEDBrightness()

        // 4 settings bytes + 6-byte calendar tail = 10-byte payload. The
        // firmware's `cmd_length >= 7` gate in lockservice_app.c then trips
        // and feeds the tail into MotionLogger_SetBootTime() so motion-log
        // event timestamps can be anchored to wall-clock time.
        var data = Data([settingsByte, deviceInfoByte, alarmDurationByte, ledBrightnessByte])
        data.append(contentsOf: Self.currentLocalCalendarBytes())
        sendData(data)
        Log.tx(.settings, "Sent settings + anchor · 0x\(String(format: "%02X", settingsByte)) deviceInfo 0x\(String(format: "%02X", deviceInfoByte)) alarmDur=\(alarmDurationByte)s ledBright=\(ledBrightnessByte)")
    }

    /// `[YY-2000, MM, DD, hh, mm, ss]` in the device user's local time.
    /// Local — not UTC — because the firmware just adds elapsed ticks and
    /// reports the result back verbatim; iOS doesn't apply a timezone on the
    /// way back in (`RESP_EVENT_DATA` builds the Date with `Calendar.current`,
    /// which is local). Keep both ends in local time so they round-trip cleanly.
    private static func currentLocalCalendarBytes() -> [UInt8] {
        let now = Date()
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let yy = UInt8(max(0, min(255, (c.year ?? 2000) - 2000)))
        return [
            yy,
            UInt8(c.month  ?? 1),
            UInt8(c.day    ?? 1),
            UInt8(c.hour   ?? 0),
            UInt8(c.minute ?? 0),
            UInt8(c.second ?? 0),
        ]
    }

    func sendPing() {
        guard !isDemoMode else { return }
        guard connectedDevice != nil else {
            Log.err(.ble, "Cannot ping · not connected")
            return
        }
        let data = Data([CMD_PING, 0x01])
        sendData(data)
        Log.tx(.ble, "Sent ping (play sound)")
    }

    func sendResetDevice() {
        guard connectedDevice != nil else {
            Log.err(.ble, "Cannot reset · not connected")
            return
        }
        let data = Data([CMD_RESET_DEVICE])
        sendData(data)
        Log.tx(.ble, "Sent device reset command")
    }

    // MARK: - Unpair (0xFD → 0xE4 0x01)

    /// Send the unbond command to the WatchDog and tear down the local bond.
    /// Calls `completion` on the main thread with `.success` once the device
    /// acks `[0xE4, 0x01]` (or `.failure(.ackTimeout)` after 2s). The peripheral
    /// is disconnected and per-device state is cleared in both paths — firmware
    /// Strategy B recovers if the ack is missed.
    func unpairDevice(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let peripheral = connectedDevice?.peripheral,
              let writeChar = writeCharacteristic,
              let token     = LoyaltyTokenStore.shared.token else {
            completion(.failure(UnpairError.notConnected))
            return
        }

        guard unpairCompletion == nil else {
            Log.warn(.bond, "Unpair already in progress")
            completion(.failure(UnpairError.notConnected))
            return
        }

        pendingUnpairDeviceID = peripheral.identifier
        unpairCompletion = completion

        var data = Data([CMD_UNBOND_DEVICE])
        data.append(token)
        peripheral.writeValue(data, for: writeChar, type: .withResponse)
        Log.tx(.bond, "Unbond (0xC0 + token)")

        DispatchQueue.main.async {
            self.unpairTimer?.invalidate()
            self.unpairTimer = Timer.scheduledTimer(withTimeInterval: self.unpairAckTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Log.warn(.bond, "Unpair ack timeout")
                self.finishUnpair(result: .failure(UnpairError.ackTimeout))
            }
        }
    }

    /// Connect to a previously-bonded device specifically to send UNBOND, then
    /// disconnect and clear local state. Used by "Forget" UI when the device
    /// isn't currently connected so the firmware EEPROM is actually wiped.
    func unpairDeviceWhileDisconnected(deviceID: UUID, completion: @escaping (Result<Void, Error>) -> Void) {
        if connectedDevice?.peripheral.identifier == deviceID {
            unpairDevice(completion: completion)
            return
        }

        guard pendingUnbondCompletion == nil else {
            Log.warn(.bond, "Unpair-while-disconnected already in progress")
            return
        }

        pendingUnbondAfterConnect = deviceID
        pendingUnbondCompletion   = completion

        connectByID(deviceID)

        DispatchQueue.main.async {
            self.unpairConnectTimer?.invalidate()
            self.unpairConnectTimer = Timer.scheduledTimer(withTimeInterval: self.unpairConnectTimeout, repeats: false) { [weak self] _ in
                guard let self = self,
                      self.pendingUnbondAfterConnect == deviceID,
                      let cb = self.pendingUnbondCompletion else { return }
                Log.warn(.bond, "Unpair-while-disconnected · connect timeout")
                self.pendingUnbondAfterConnect = nil
                self.pendingUnbondCompletion = nil
                self.unpairConnectTimer = nil
                self.suppressAutoReconnect = true
                self.stopReconnecting()
                cb(.failure(UnpairError.notConnected))
            }
        }
    }

    private func handleUnpairAck() {
        guard unpairCompletion != nil else { return }
        Log.ok(.bond, "Unpair ack received [0xE4 0x01]")
        finishUnpair(result: .success(()))
    }

    private func finishUnpair(result: Result<Void, Error>) {
        guard let completion = unpairCompletion else { return }
        unpairCompletion = nil
        unpairTimer?.invalidate()
        unpairTimer = nil

        let deviceID = pendingUnpairDeviceID
        pendingUnpairDeviceID = nil

        suppressAutoReconnect = true
        stopReconnecting()

        if let peripheral = connectedDevice?.peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        if let deviceID = deviceID {
            clearLocalStateAfterUnpair(for: deviceID)
        }

        DispatchQueue.main.async {
            completion(result)
        }
    }

    // MARK: - Loyalty Handshake (CLAIM/VERIFY/REJECT)

    private func startLoyaltyHandshake() {
        guard let peripheral = connectedDevice?.peripheral,
              let writeChar  = writeCharacteristic,
              let token      = LoyaltyTokenStore.shared.token else {
            Log.err(.loyalty, "Handshake · missing prerequisites")
            return
        }

        // Re-read bond state at the latest possible moment. If we just
        // unpaired, BondManager will already reflect the removal. A stale
        // isBonded() value would cause us to send VERIFY against an empty
        // EEPROM and get REJECTed. (Sending CLAIM on an unowned device is
        // also handled correctly by the firmware as of FW Vx.y.z — see
        // TheWatchDogBT/UNBOND_CLAIM_FIX_PROMPT.md.)
        let isFirstClaim = !BondManager.shared.isBonded(deviceID: peripheral.identifier)

        let opcode: UInt8 = isFirstClaim ? CMD_CLAIM_DEVICE : CMD_VERIFY_OWNER
        var payload = Data([opcode])
        payload.append(token)

        let tokenHex = token.map { String(format: "%02X", $0) }.joined()
        let opName = isFirstClaim ? "CLAIM" : "VERIFY"
        Log.info(.loyalty, "token=\(tokenHex) op=\(opName)")

        peripheral.writeValue(payload, for: writeChar, type: .withResponse)
        DispatchQueue.main.async { [weak self] in
            self?.loyaltyState = isFirstClaim ? .awaitingClaimAck : .awaitingVerifyAck
            self?.startLoyaltyTimer()
        }
        Log.tx(.loyalty, "\(opName) · bond=\(BondManager.shared.isBonded(deviceID: peripheral.identifier))")
    }

    private func startLoyaltyTimer() {
        loyaltyTimer?.invalidate()
        loyaltyTimer = Timer.scheduledTimer(withTimeInterval: loyaltyTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                Log.warn(.loyalty, "Timeout in state \(self.loyaltyState)")
                self.handleLoyaltyTimeout()
            }
        }
    }

    private func handleLoyaltyTimeout() {
        switch loyaltyState {
        case .awaitingClaimAck, .awaitingVerifyAck:
            notYourDeviceAlert = "Couldn't reach this WatchDog. Try again."
            if let peripheral = connectedDevice?.peripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            loyaltyState = .idle
        default:
            break
        }
    }

    private func handleClaimOk() {
        Log.ok(.loyalty, "CLAIM_OK")
        loyaltyTimer?.invalidate(); loyaltyTimer = nil
        loyaltyState = .verified
        if let peripheral = connectedDevice?.peripheral {
            let name = connectedDevice?.name ?? "WatchDog"
            BondManager.shared.addBond(deviceID: peripheral.identifier, name: name)
        }
        onLoyaltyVerifiedHook()
    }

    private func handleVerifyOk() {
        Log.ok(.loyalty, "VERIFY_OK")
        loyaltyTimer?.invalidate(); loyaltyTimer = nil
        loyaltyState = .verified
        // Defensive: if firmware returns VERIFY_OK in response to a CLAIM
        // (e.g. iPhone wiped local bonds but firmware EEPROM still holds this
        // token), the local bond never got recorded — leaving the user on
        // the add-device screen with a live BLE connection. addBond is
        // idempotent, so this is safe even on legitimate VERIFY paths.
        if let peripheral = connectedDevice?.peripheral,
           !BondManager.shared.isBonded(deviceID: peripheral.identifier) {
            let name = connectedDevice?.name ?? "WatchDog"
            BondManager.shared.addBond(deviceID: peripheral.identifier, name: name)
        }
        onLoyaltyVerifiedHook()
    }

    private func handleReject() {
        Log.err(.loyalty, "REJECT · not this iPhone's WatchDog")
        loyaltyTimer?.invalidate(); loyaltyTimer = nil
        loyaltyState = .rejected

        let rejectedID = connectedDevice?.peripheral.identifier
        let wasBonded  = rejectedID.map { BondManager.shared.isBonded(deviceID: $0) } ?? false

        DispatchQueue.main.async { [weak self] in
            if wasBonded, let id = rejectedID {
                // We thought we owned this WatchDog but the firmware says no.
                // Most likely cause: device was hardware-reset (cable-hold) on
                // the firmware side and is now unowned. Clear local bond so
                // the user can re-claim it on the next tap.
                BondManager.shared.removeBond(deviceID: id)
                self?.notYourDeviceAlert = "This WatchDog has been reset. Tap it again to re-pair."
            } else {
                self?.notYourDeviceAlert = "Not your device!"
            }
        }

        if let peripheral = connectedDevice?.peripheral {
            suppressAutoReconnect = true
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    /// Called once after CLAIM_OK or VERIFY_OK. Triggers the deferred
    /// "we're now ready to send normal commands" work that used to run
    /// unconditionally 1.0 s post-connect.
    private func onLoyaltyVerifiedHook() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.connectedDevice != nil else { return }
            // Anchor firmware's clock before pulling logs — otherwise events
            // generated this session arrive with the unknown-time sentinel.
            self.sendSettings()
            self.requestMotionLogCount()
        }
    }

    // MARK: - Diagnostic (0xF4 → BATTERYDIAG TLV)

    /// Request a one-shot TLV diagnostic from the WatchDog. The response
    /// arrives as a single notification on the BATTERYDIAG characteristic.
    /// `completion` fires on the main thread with the parsed report or an error.
    /// Throttled to one request per `diagnosticMinInterval` (firmware caches
    /// battery state on a 1 s tick — faster requests just return the same data).
    func requestDiagnostic(sectionMask: UInt8 = 0xFF,
                           completion: @escaping (Result<DiagnosticReport, Error>) -> Void) {
        guard connectedDevice?.peripheral != nil,
              writeCharacteristic != nil else {
            completion(.failure(DiagnosticError.notConnected))
            return
        }

        guard diagnosticCompletion == nil else {
            Log.warn(.diag, "Diagnostic already in progress")
            return
        }

        if let last = lastDiagnosticRequestAt,
           Date().timeIntervalSince(last) < diagnosticMinInterval {
            Log.warn(.diag, "Throttled · last request <1s ago")
            // Don't error — this is a UX guardrail, not a failure. Caller's
            // completion never fires; UI should debounce its own button.
            return
        }
        lastDiagnosticRequestAt = Date()

        diagnosticCompletion = completion

        sendData(Data([BluetoothManager.CMD_REQUEST_DIAG, sectionMask]))
        Log.tx(.diag, String(format: "Diagnostic request (0xF4 mask=0x%02X)", sectionMask))

        DispatchQueue.main.async {
            self.diagnosticTimer?.invalidate()
            self.diagnosticTimer = Timer.scheduledTimer(withTimeInterval: self.diagnosticTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Log.warn(.diag, "Diagnostic timeout")
                self.finishDiagnostic(result: .failure(DiagnosticError.timeout))
            }
        }
    }

    private func handleDiagnosticResponse(data: Data) {
        guard diagnosticCompletion != nil else { return }
        guard let report = DiagnosticReport(data) else {
            Log.err(.diag, "Malformed TLV · \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            finishDiagnostic(result: .failure(DiagnosticError.malformedResponse))
            return
        }
        Log.ok(.diag, "TLV v\(report.formatVersion) · \(report.sections.count) section(s)")
        finishDiagnostic(result: .success(report))
    }

    private func finishDiagnostic(result: Result<DiagnosticReport, Error>) {
        guard let completion = diagnosticCompletion else { return }
        diagnosticCompletion = nil
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func clearLocalStateAfterUnpair(for deviceID: UUID) {
        // Synchronous main-thread cleanup: must complete before any
        // re-pair attempt can read BondManager. Otherwise a fast retap
        // would see isBonded=true and send VERIFY against an empty EEPROM.
        let work = { [self] in
            if reconnectTargetDeviceID == deviceID {
                reconnectTargetDeviceID = nil
                isAttemptingReconnect = false
            }
            watchDogIdentifiers.removeValue(forKey: deviceID)
            watchDogFirmwares.removeValue(forKey: deviceID)
            loyaltyState = .idle

            if NavigationStateManager.shared.lastDeviceID == deviceID {
                NavigationStateManager.shared.saveDeviceList()
            }

            MotionLogManager.shared.clearAllEvents(for: deviceID)
            BondManager.shared.removeBond(deviceID: deviceID)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    // MARK: - Motion Log Sync

    func startMotionLogPolling(interval: TimeInterval = 0.25) {
        stopMotionLogPolling()
        // Re-anchor the firmware clock right before pulling logs. TickToDateTime
        // computes calendar time as (boot_time + elapsed_ms_since_anchor) — a
        // fresh anchor minimizes accumulated quartz drift on each view session.
        sendSettings()
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

    /// Background drain trigger — pulls anything fresh in the firmware ring
    /// without requiring the user to open the Motion Report screen. Bails
    /// silently if no device is connected, loyalty isn't verified yet, or a
    /// drain is already in flight (the existing `isSyncingMotionLogs` flag
    /// gates concurrent drains the same way `startMotionLogPolling` did).
    /// Called from: ARMED-bit transitions (to pick up SESSION_START/END
    /// markers promptly), motion-alert receipt (to pick up the underlying
    /// MotionEvent rather than waiting on a periodic poll).
    func triggerOpportunisticLogDrain() {
        guard connectedDevice != nil,
              loyaltyState == .verified,
              !isSyncingMotionLogs else { return }
        requestMotionLogCount()
    }

    /// Two-shot drain used after an ARMED 1→0 transition. The firmware
    /// logs SESSION_END inside StateMachine_ChangeState, which is reached
    /// the next time the state-machine loop iterates — almost always
    /// within single-digit ms of receiving the disarm settings packet,
    /// but a slow main loop or a deferred-EEPROM flush after ALARM_ACTIVE
    /// could push it past the first drain. Schedule a second pull ~2 s
    /// later so the SESSION_END almost certainly lands before the 5 s
    /// watchdog gives up and marks the session INCOMPLETE.
    private func scheduleFollowupDisarmDrain() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.triggerOpportunisticLogDrain()
        }
    }
    
    func requestMotionEvent(at index: UInt16) {
        let data = Data([CMD_REQUEST_EVENT, UInt8((index >> 8) & 0xFF), UInt8(index & 0xFF)])
        sendData(data)
        armEventFetchWatchdog(forIndex: index)
    }

    func clearMotionLog() {
        let data = Data([CMD_CLEAR_LOG])
        sendData(data)
    }

    private func armEventFetchWatchdog(forIndex index: UInt16) {
        eventFetchWatchdog?.invalidate()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.eventFetchWatchdog = Timer.scheduledTimer(withTimeInterval: self.eventFetchTimeoutSeconds,
                                                          repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Log.warn(.motion, "Event fetch timed out at idx \(index) · ending sync")
                self.isSyncingMotionLogs = false
                self.eventFetchWatchdog = nil
            }
        }
    }

    private func cancelEventFetchWatchdog() {
        eventFetchWatchdog?.invalidate()
        eventFetchWatchdog = nil
    }
    
    private func handleMotionLogResponse(data: Data) {
        guard data.count >= 1 else { return }
        let responseType = data[0]
        
        switch responseType {
        case RESP_LOG_COUNT:
            guard data.count >= 3 else { return }
            let count = (UInt16(data[1]) << 8) | UInt16(data[2])
            Log.rx(.motion, "Log count · \(count)")
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
            cancelEventFetchWatchdog()
            let index = (UInt16(data[1]) << 8) | UInt16(data[2])
            let year = data[3], month = data[4], day = data[5]
            let hour = data[6], minute = data[7], second = data[8]
            let motionType = data[9]
            let batteryByte = data[10]

            let timestamp: Date? = {
                // Firmware's unanchored sentinel is (year=0, month=1, day=1, 00:00:00).
                // Treat as missing rather than fabricating a wall-clock time —
                // the UI renders nil as "Unknown time".
                if year == 0 && month == 1 && day == 1 && hour == 0 && minute == 0 && second == 0 {
                    return nil
                }
                // Range-check every field. The old firmware's anchor-drift
                // bug could emit values like year=255 / month=12 / day=31
                // that DateComponents would silently coerce into real-but-
                // wrong dates (e.g. year 2255). With the new firmware these
                // shouldn't appear, but treating out-of-range as "unknown"
                // is cheap insurance against future regressions.
                guard year  <= 99,
                      month >= 1, month <= 12,
                      day   >= 1, day   <= 31,
                      hour   <= 23,
                      minute <= 59,
                      second <= 59 else {
                    return nil
                }
                var components = DateComponents()
                components.year   = 2000 + Int(year)
                components.month  = Int(month)
                components.day    = Int(day)
                components.hour   = Int(hour)
                components.minute = Int(minute)
                components.second = Int(second)
                return Calendar.current.date(from: components)
            }()

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
            cancelEventFetchWatchdog()
            DispatchQueue.main.async { self.isSyncingMotionLogs = false }

        case RESP_LOG_CLEARED:
            cancelEventFetchWatchdog()
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
        Log.info(.ble, "Scan ensured after foreground return")
    }
    
    // MARK: - Reconnection Support
    
    func startReconnecting(to deviceID: UUID) {
        guard !suppressAutoReconnect else {
            Log.warn(.ble, "Auto-reconnect suppressed")
            return
        }

        if isAttemptingReconnect && reconnectTargetDeviceID == deviceID {
            return
        }

        reconnectTargetDeviceID = deviceID
        DispatchQueue.main.async {
            self.isAttemptingReconnect = true
        }

        Log.info(.ble, "Will reconnect to [\(deviceID.uuidString.prefix(8))] when discovered")
        ensureScanning()
    }

    func stopReconnecting() {
        let wasReconnecting = isAttemptingReconnect
        DispatchQueue.main.async {
            self.reconnectTargetDeviceID = nil
            self.isAttemptingReconnect = false
        }
        if wasReconnecting {
            Log.info(.ble, "Stopped reconnection attempts")
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

        Log.info(.ble, "Target discovered · connecting immediately")
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
                Log.ok(.ble, "Bluetooth powered on")
                self.ensureScanning()
            case .poweredOff:
                Log.err(.ble, "Bluetooth powered off")
                self.isScanning = false
                self.connectedDevice = nil
            case .unauthorized:
                Log.warn(.ble, "Bluetooth unauthorized")
            case .unsupported:
                Log.err(.ble, "Bluetooth unsupported")
            case .resetting:
                Log.info(.ble, "Bluetooth resetting")
                self.isScanning = false
            case .unknown:
                Log.warn(.ble, "Bluetooth state unknown")
            @unknown default:
                Log.warn(.ble, "Bluetooth state unknown")
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
                Log.info(.ble, "Discovered \(name) [\(deviceID.uuidString.prefix(8))] · RSSI \(RSSI.intValue)dBm")
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
        Log.ok(.ble, "Connected to \(peripheral.name ?? "Unknown") [\(peripheral.identifier.uuidString.prefix(8))]")

        // Demo mode: a connection that completes after enterDemoMode would
        // overwrite `connectedDevice` and re-arm the BLE plumbing. Cancel and
        // ignore.
        if isDemoMode {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

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
            Log.err(.ble, "Disconnected from \(peripheral.name ?? "Unknown") · \(error.localizedDescription)")
        } else {
            Log.info(.ble, "Disconnected from \(peripheral.name ?? "Unknown")")
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
        Log.err(.ble, "Failed to connect · \(error?.localizedDescription ?? "Unknown error")")

        DispatchQueue.main.async {
            self.connectionTimer?.invalidate()
            self.connectionTimer = nil
            self.isConnecting = false
            self.pendingConnectionPeripheral = nil

            if self.isAttemptingReconnect {
                Log.info(.ble, "Connection failed — will retry on next advertisement")
            }
            // Scanning still alive — no restart needed
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            Log.err(.ble, "discoverServices · \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            Log.err(.ble, "discoverCharacteristics · \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                Log.ok(.ble, "Write characteristic found")
            }

            if characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                Log.ok(.ble, "Subscribed to notifications")
            }
            
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
        
        // Loyalty handshake — gates all subsequent normal commands.
        // Exception: if the user invoked unpair-while-disconnected and we
        // connected specifically to send UNBOND, route there instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            if let pending = self.pendingUnbondAfterConnect,
               pending == peripheral.identifier {
                self.pendingUnbondAfterConnect = nil
                self.unpairConnectTimer?.invalidate()
                self.unpairConnectTimer = nil
                let cb = self.pendingUnbondCompletion ?? { _ in }
                self.pendingUnbondCompletion = nil
                self.unpairDevice(completion: cb)
            } else {
                self.startLoyaltyHandshake()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Log.err(.ble, "Notification state update · \(error.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Log.err(.ble, "Read characteristic · \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value, data.count >= 1 else { return }

        // Demo mode owns the published state. Stale notifications can arrive
        // between `cancelPeripheralConnection` and `didDisconnect`, and they
        // would overwrite the demo defaults (battery, MLC, accel, etc.).
        if isDemoMode { return }

        // ─── BATTERYDIAG characteristic — now carries the TLV diagnostic blob ───
        // Firmware no longer auto-pushes; this only fires in response to 0xF4.
        if characteristic.uuid == batteryDiagCharacteristicUUID {
            DispatchQueue.main.async {
                self.handleDiagnosticResponse(data: data)
            }
            return
        }

        let firstByte = data[0]

        // ─── Loyalty handshake responses ───
        if data.count >= 2 {
            switch firstByte {
            case RESP_CLAIM_OK:
                DispatchQueue.main.async { self.handleClaimOk() }
                return
            case RESP_VERIFY_OK:
                DispatchQueue.main.async { self.handleVerifyOk() }
                return
            case RESP_REJECT:
                DispatchQueue.main.async { self.handleReject() }
                return
            default:
                break
            }
        }

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
                // Pull the underlying MotionEvent (and any SESSION marker
                // that may have just been logged alongside it) from the
                // firmware ring. The alert payload carries only the type
                // byte — the wall-clock timestamp lives in the log entry,
                // and we don't want to wait on the next polling cycle for
                // the user-visible record to appear.
                self.triggerOpportunisticLogDrain()
            }
            return
        }
        
        // ─── Unpair ack (0xE4 0x01) ───
        if firstByte == RESP_UNPAIR_ACK {
            if data.count >= 2 && data[1] == 0x01 {
                DispatchQueue.main.async {
                    self.handleUnpairAck()
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

        let watchDogID: UInt16? = data.count >= 16
            ? (UInt16(data[15]) << 8) | UInt16(data[14])
            : nil

        // 19-byte frame adds firmware version; older 16-byte frames have none.
        let firmware: WatchDogFirmware? = data.count >= 19
            ? WatchDogFirmware(major: data[16], main: data[17], v2: data[18])
            : nil
        let peripheralID = peripheral.identifier

        DispatchQueue.main.async {
            if let watchDogID {
                self.watchDogIdentifiers[peripheralID] = watchDogID
            }
            if let firmware {
                self.watchDogFirmwares[peripheralID] = firmware
            }
            // Capture the pre-write ARMED bit so we can notice transitions
            // (1→0 starts the post-disarm watchdog in MotionSessionsRepository;
            // 0→1 clears stale watchdog state and opens a new session). The
            // transition is also the moment a SESSION_START / SESSION_END
            // marker has just been logged firmware-side, so kick an opportunistic
            // drain so the marker doesn't sit in the firmware ring waiting on
            // the next motion event to pull it.
            let priorArmed = (self.deviceState & 0x01) != 0
            self.deviceState = settingsByte
            self.hasReceivedInitialState = true
            self.settingsManager.decodeSettings(from: settingsByte)
            if let deviceInfoByte { self.settingsManager.decodeDeviceInfo(from: deviceInfoByte) }
            let newArmed = (settingsByte & 0x01) != 0
            if priorArmed != newArmed {
                MotionSessionsRepository.shared.noteArmedStateChange(armed: newArmed)
                self.triggerOpportunisticLogDrain()
                if priorArmed && !newArmed {
                    self.scheduleFollowupDisarmDrain()
                }
            }

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
            // All three arrays append in lockstep, so they share the same cutoff index.
            if let dropCount = self.accelXHistory.firstIndex(where: { $0.date >= cutoff }), dropCount > 0 {
                self.accelXHistory.removeFirst(dropCount)
                self.accelYHistory.removeFirst(dropCount)
                self.accelZHistory.removeFirst(dropCount)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Log.err(.ble, "Write · \(error.localizedDescription)")
        }
    }
}
