//
//  SettingsManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation
import Observation

@Observable
class SettingsManager {
    static let shared = SettingsManager()

    // The device whose settings are currently loaded
    private(set) var currentDeviceID: UUID?

    // Observable properties for UI binding
    var isArmed: Bool = false
    var alarmType: AlarmType = .normal
    var sensitivity: SensitivityLevel = .medium
    var lightsEnabled: Bool = true
    var loggingEnabled: Bool = false
    var disableAlarmWhenConnected: Bool = false
    var deviceName: String = "WatchDog"
    var debugModeEnabled: Bool = false
    var highPerformanceMode: Bool = false
    var liveOrientationEnabled: Bool = false
    var devModeUnlocked: Bool = false
    var dataLoggingMode: Bool = false
    var alarmTriggers: Set<MotionEventType> = [.shaken, .impact, .freefall, .tilted, .doorOpening, .doorClosing]
    var selectedPresetRawValue: String = "maxSecurity"
    /// Seconds the alarm continues to sound after motion stops. Range 0...30.
    var alarmDuration: Int = 2
    /// When true, the WatchDog suppresses the alarm entirely regardless of
    /// trigger conditions. Persisted per-device.
    var alarmDisabled: Bool = false
    /// When true, the WatchDog skips the three-tone descending chime that
    /// otherwise plays whenever the BLE link drops. Independent of
    /// `alarmDisabled`. Firmware ≥ V1.11.26. Persisted per-device.
    var disconnectSoundDisabled: Bool = false
    /// LED brightness in app units (1...100). Mapped to firmware's 1...255 on send.
    var ledBrightness: Int = 100
    /// BLE radio TX power. `normal` = 0 dBm, `highPower` = +8 dBm. Default is
    /// `highPower` so first-pair behaviour matches the legacy firmware
    /// (which booted at +8 dBm before this setting existed). Persisted
    /// per-device. Firmware ≥ V1.12.11.
    var bleTxPower: BleTxPower = .highPower

    /// True while a DemoSession is active. Persistence calls (`saveDeviceSettings`,
    /// `saveGlobalSettings`, `setPersistedArmed`) become no-ops so the demo's
    /// settings live only in memory. The pre-demo state is snapshotted in
    /// `enterDemoMode()` and restored verbatim by `exitDemoMode()`.
    private(set) var isDemoMode: Bool = false
    private var demoSnapshot: DemoSnapshot?

    private struct DemoSnapshot {
        var currentDeviceID: UUID?
        var isArmed: Bool
        var alarmType: AlarmType
        var sensitivity: SensitivityLevel
        var lightsEnabled: Bool
        var loggingEnabled: Bool
        var disableAlarmWhenConnected: Bool
        var deviceName: String
        var debugModeEnabled: Bool
        var highPerformanceMode: Bool
        var liveOrientationEnabled: Bool
        var devModeUnlocked: Bool
        var dataLoggingMode: Bool
        var alarmTriggers: Set<MotionEventType>
        var selectedPresetRawValue: String
        var alarmDuration: Int
        var alarmDisabled: Bool
        var disconnectSoundDisabled: Bool
        var ledBrightness: Int
        var bleTxPower: BleTxPower
    }

    // UserDefaults keys — per-device settings
    private let armedKey = "watchdog_armed"
    private let alarmTypeKey = "watchdog_alarm_type"
    private let sensitivityKey = "watchdog_sensitivity"
    private let lightsKey = "watchdog_lights"
    private let loggingKey = "watchdog_logging"
    private let disableAlarmWhenConnectedKey = "watchdog_disable_alarm_connected"
    private let alarmTriggersKey = "watchdog_alarm_triggers"
    private let selectedPresetKey = "watchdog_selected_preset"
    private let alarmDurationKey = "watchdog_alarm_duration"
    private let alarmDisabledKey = "watchdog_alarm_disabled"
    private let disconnectSoundDisabledKey = "watchdog_disconnect_sound_disabled"
    private let ledBrightnessKey = "watchdog_led_brightness"
    private let bleTxPowerKey = "watchdog_ble_tx_power"

    // UserDefaults keys — global settings
    private let deviceNameKey = "watchdog_device_name"
    private let debugModeKey = "watchdog_debug_mode"
    private let liveOrientationKey = "watchdog_live_orientation"
    private let devModeUnlockedKey = "watchdog_dev_mode_unlocked"
    private let dataLoggingModeKey = "watchdog_data_logging_mode"

    private init() {
        loadGlobalSettings()
    }

    private func deviceKey(_ base: String, _ deviceID: UUID) -> String {
        "\(deviceID.uuidString)_\(base)"
    }

    /// Read a device's persisted armed state without mutating the shared in-memory state.
    func persistedArmed(for deviceID: UUID) -> Bool {
        let ud = UserDefaults.standard
        let key = deviceKey(armedKey, deviceID)
        return ud.object(forKey: key) != nil ? ud.bool(forKey: key) : false
    }

    /// Write a device's armed state directly to UserDefaults without touching the shared in-memory state.
    func setPersistedArmed(_ value: Bool, for deviceID: UUID) {
        guard !isDemoMode else { return }
        UserDefaults.standard.set(value, forKey: deviceKey(armedKey, deviceID))
    }
    
    // MARK: - Byte Encoding/Decoding
    
    /// Encodes current settings into a single byte
    /// Bit layout:
    /// - Bit 0: Armed (0=unlocked, 1=locked)
    /// - Bits 1-2: Alarm Type (00=None, 01=Calm, 10=Normal, 11=Loud)
    /// - Bits 3-4: Sensitivity (00=Low, 01=Medium, 10=High)
    /// - Bit 5: Lights (0=Off, 1=On)
    /// - Bit 6: Logging (0=Off, 1=On)
    /// - Bit 7: Disable Alarm When Connected (0=Alarm always, 1=Disable when connected)
    func encodeSettings() -> UInt8 {
        var byte: UInt8 = 0
        
        // Bit 0: Armed
        if isArmed {
            byte |= (1 << 0)
        }
        
        // Bits 1-2: Alarm Type
        let alarmBits = alarmType.bitValue
        byte |= (alarmBits << 1)
        
        // Bits 3-4: Sensitivity
        let sensitivityBits = sensitivity.bitValue
        byte |= (sensitivityBits << 3)
        
        // Bit 5: Lights
        if lightsEnabled {
            byte |= (1 << 5)
        }
        
        // Bit 6: Logging
        if loggingEnabled {
            byte |= (1 << 6)
        }
        
        // Bit 7: Disable Alarm When Connected
        if disableAlarmWhenConnected {
            byte |= (1 << 7)
        }
        
        return byte
    }
    
    /// Encodes deviceInfo into a single byte (byte 13)
    /// Bit 0: High Performance Mode
    /// Bit 1: Alarm Disabled (1 = alarm fully suppressed regardless of triggers)
    /// Bit 2: Disconnect Sound Disabled (1 = three-tone chime on BLE drop is suppressed; firmware ≥ V1.11.26)
    func encodeDeviceInfo() -> UInt8 {
        var byte: UInt8 = 0
        if highPerformanceMode {
            byte |= (1 << 0)
        }
        if alarmDisabled {
            byte |= (1 << 1)
        }
        if disconnectSoundDisabled {
            byte |= (1 << 2)
        }
        return byte
    }

    /// Encodes alarm duration as a single byte. Value is seconds (0...30); clamped on send.
    func encodeAlarmDuration() -> UInt8 {
        UInt8(max(0, min(30, alarmDuration)))
    }

    /// Maps app-side LED brightness (1...100) to firmware scale (1...255).
    func encodeLEDBrightness() -> UInt8 {
        let clamped = max(1, min(100, ledBrightness))
        let scaled = 1 + Int(round((Double(clamped - 1) / 99.0) * 254.0))
        return UInt8(max(1, min(255, scaled)))
    }

    /// Encodes the BLE TX power level — single byte at cmd_data[4] in the
    /// settings write. Firmware enum: 0 = NORMAL (0 dBm), 1 = HIGH (+8 dBm).
    func encodeBleTxPower() -> UInt8 {
        bleTxPower.bitValue
    }

    /// Decodes deviceInfo byte from WatchDog. Bit 3 carries the BLE TX power
    /// level (0 = NORMAL, 1 = HIGH). Firmware ≥ V1.12.11.
    func decodeDeviceInfo(from byte: UInt8) {
        highPerformanceMode = (byte & (1 << 0)) != 0
        alarmDisabled = (byte & (1 << 1)) != 0
        disconnectSoundDisabled = (byte & (1 << 2)) != 0
        bleTxPower = BleTxPower.from(bitValue: (byte >> 3) & 0b1)
        Log.info(.settings, "deviceInfo · highPerformance=\(highPerformanceMode) alarmDisabled=\(alarmDisabled) disconnectSoundDisabled=\(disconnectSoundDisabled) bleTxPower=\(bleTxPower.rawValue)")
        saveDeviceSettings()
    }

    /// Decodes a byte from WatchDog into settings
    func decodeSettings(from byte: UInt8) {
        // Bit 0: Armed
        isArmed = (byte & (1 << 0)) != 0

        // Bits 1-2: Alarm Type
        let alarmBits = (byte >> 1) & 0b11
        alarmType = AlarmType.from(bitValue: alarmBits)

        // Bits 3-4: Sensitivity
        let sensitivityBits = (byte >> 3) & 0b11
        sensitivity = SensitivityLevel.from(bitValue: sensitivityBits)

        // Bit 5: Lights
        lightsEnabled = (byte & (1 << 5)) != 0

        // Bit 6: Logging
        loggingEnabled = (byte & (1 << 6)) != 0

        // Bit 7: Disable Alarm When Connected
        disableAlarmWhenConnected = (byte & (1 << 7)) != 0

        let lockGlyph = isArmed ? "🔒 Armed" : "🔓 Idle"
        Log.rx(.settings, "0x\(String(format: "%02X", byte)) · \(lockGlyph) · alarm=\(alarmType.rawValue) · sens=\(sensitivity.rawValue) · lights=\(lightsEnabled ? "on" : "off") · log=\(loggingEnabled ? "on" : "off") · disableWhenConn=\(disableAlarmWhenConnected)")

        // Save to UserDefaults (WatchDog is source of truth)
        saveDeviceSettings()
    }
    
    // MARK: - Per-Device Persistence

    /// Load settings for a specific device into memory
    func loadDeviceSettings(for deviceID: UUID) {
        currentDeviceID = deviceID
        let ud = UserDefaults.standard

        isArmed = ud.object(forKey: deviceKey(armedKey, deviceID)) != nil
            ? ud.bool(forKey: deviceKey(armedKey, deviceID))
            : false

        if let s = ud.string(forKey: deviceKey(alarmTypeKey, deviceID)),
           let v = AlarmType(rawValue: s) {
            alarmType = v
        } else {
            alarmType = .normal
        }

        if let s = ud.string(forKey: deviceKey(sensitivityKey, deviceID)),
           let v = SensitivityLevel(rawValue: s) {
            sensitivity = v
        } else {
            sensitivity = .medium
        }

        lightsEnabled = ud.object(forKey: deviceKey(lightsKey, deviceID)) != nil
            ? ud.bool(forKey: deviceKey(lightsKey, deviceID))
            : true

        loggingEnabled = ud.object(forKey: deviceKey(loggingKey, deviceID)) != nil
            ? ud.bool(forKey: deviceKey(loggingKey, deviceID))
            : false

        disableAlarmWhenConnected = ud.object(forKey: deviceKey(disableAlarmWhenConnectedKey, deviceID)) != nil
            ? ud.bool(forKey: deviceKey(disableAlarmWhenConnectedKey, deviceID))
            : false

        highPerformanceMode = devModeUnlocked

        if let saved = ud.array(forKey: deviceKey(alarmTriggersKey, deviceID)) as? [UInt8] {
            alarmTriggers = Set(saved.compactMap { MotionEventType(rawValue: $0) })
        } else {
            alarmTriggers = [.shaken, .impact, .freefall, .tilted, .doorOpening, .doorClosing]
        }

        if let s = ud.string(forKey: deviceKey(selectedPresetKey, deviceID)) {
            selectedPresetRawValue = s
        } else {
            selectedPresetRawValue = "maxSecurity"
        }

        if ud.object(forKey: deviceKey(alarmDurationKey, deviceID)) != nil {
            alarmDuration = max(1, min(30, ud.integer(forKey: deviceKey(alarmDurationKey, deviceID))))
        } else {
            alarmDuration = 2
        }

        alarmDisabled = ud.object(forKey: deviceKey(alarmDisabledKey, deviceID)) != nil
            ? ud.bool(forKey: deviceKey(alarmDisabledKey, deviceID))
            : false

        disconnectSoundDisabled = ud.object(forKey: deviceKey(disconnectSoundDisabledKey, deviceID)) != nil
            ? ud.bool(forKey: deviceKey(disconnectSoundDisabledKey, deviceID))
            : false

        if ud.object(forKey: deviceKey(ledBrightnessKey, deviceID)) != nil {
            ledBrightness = max(1, min(100, ud.integer(forKey: deviceKey(ledBrightnessKey, deviceID))))
        } else {
            ledBrightness = 100
        }

        if let s = ud.string(forKey: deviceKey(bleTxPowerKey, deviceID)),
           let v = BleTxPower(rawValue: s) {
            bleTxPower = v
        } else {
            bleTxPower = .highPower
        }
    }

    private func saveDeviceSettings() {
        guard !isDemoMode else { return }
        guard let deviceID = currentDeviceID else { return }
        let ud = UserDefaults.standard

        ud.set(isArmed, forKey: deviceKey(armedKey, deviceID))
        ud.set(alarmType.rawValue, forKey: deviceKey(alarmTypeKey, deviceID))
        ud.set(sensitivity.rawValue, forKey: deviceKey(sensitivityKey, deviceID))
        ud.set(lightsEnabled, forKey: deviceKey(lightsKey, deviceID))
        ud.set(loggingEnabled, forKey: deviceKey(loggingKey, deviceID))
        ud.set(disableAlarmWhenConnected, forKey: deviceKey(disableAlarmWhenConnectedKey, deviceID))
        ud.set(alarmTriggers.map { $0.rawValue }, forKey: deviceKey(alarmTriggersKey, deviceID))
        ud.set(selectedPresetRawValue, forKey: deviceKey(selectedPresetKey, deviceID))
        ud.set(alarmDuration, forKey: deviceKey(alarmDurationKey, deviceID))
        ud.set(alarmDisabled, forKey: deviceKey(alarmDisabledKey, deviceID))
        ud.set(disconnectSoundDisabled, forKey: deviceKey(disconnectSoundDisabledKey, deviceID))
        ud.set(ledBrightness, forKey: deviceKey(ledBrightnessKey, deviceID))
        ud.set(bleTxPower.rawValue, forKey: deviceKey(bleTxPowerKey, deviceID))
    }

    // MARK: - Global Persistence

    private func saveGlobalSettings() {
        guard !isDemoMode else { return }
        let ud = UserDefaults.standard
        ud.set(deviceName, forKey: deviceNameKey)
        ud.set(debugModeEnabled, forKey: debugModeKey)
        ud.set(liveOrientationEnabled, forKey: liveOrientationKey)
        ud.set(devModeUnlocked, forKey: devModeUnlockedKey)
        ud.set(dataLoggingMode, forKey: dataLoggingModeKey)
    }

    private func loadGlobalSettings() {
        let ud = UserDefaults.standard
        deviceName = ud.string(forKey: deviceNameKey) ?? "WatchDog"
        debugModeEnabled = ud.object(forKey: debugModeKey) != nil ? ud.bool(forKey: debugModeKey) : false
        liveOrientationEnabled = ud.object(forKey: liveOrientationKey) != nil ? ud.bool(forKey: liveOrientationKey) : false
        devModeUnlocked = ud.object(forKey: devModeUnlockedKey) != nil ? ud.bool(forKey: devModeUnlockedKey) : false
        dataLoggingMode = ud.object(forKey: dataLoggingModeKey) != nil ? ud.bool(forKey: dataLoggingModeKey) : false
    }

    // MARK: - Update

    /// Call this when user manually changes settings
    func updateSettings(name: String? = nil, armed: Bool? = nil, alarm: AlarmType? = nil,
                       sens: SensitivityLevel? = nil, lights: Bool? = nil, logging: Bool? = nil,
                       disableAlarmConnected: Bool? = nil, debugMode: Bool? = nil,
                       highPerformance: Bool? = nil, liveOrientation: Bool? = nil,
                       dataLogging: Bool? = nil, triggers: Set<MotionEventType>? = nil,
                       preset: String? = nil, alarmDuration: Int? = nil,
                       alarmDisabled: Bool? = nil, disconnectSoundDisabled: Bool? = nil,
                       ledBrightness: Int? = nil, bleTxPower: BleTxPower? = nil) {
        if let name = name { deviceName = name }
        if let armed = armed { isArmed = armed }
        if let alarm = alarm { alarmType = alarm }
        if let sens = sens { sensitivity = sens }
        if let lights = lights { lightsEnabled = lights }
        if let logging = logging { loggingEnabled = logging }
        if let disableAlarmConnected = disableAlarmConnected { disableAlarmWhenConnected = disableAlarmConnected }
        if let debugMode = debugMode { debugModeEnabled = debugMode }
        if let highPerformance = highPerformance { highPerformanceMode = highPerformance }
        if let liveOrientation = liveOrientation { liveOrientationEnabled = liveOrientation }
        if let dataLogging = dataLogging { dataLoggingMode = dataLogging }
        if let triggers = triggers { alarmTriggers = triggers }
        if let preset = preset { selectedPresetRawValue = preset }
        if let alarmDuration = alarmDuration {
            self.alarmDuration = max(1, min(30, alarmDuration))
        }
        if let alarmDisabled = alarmDisabled { self.alarmDisabled = alarmDisabled }
        if let disconnectSoundDisabled = disconnectSoundDisabled {
            self.disconnectSoundDisabled = disconnectSoundDisabled
        }
        if let ledBrightness = ledBrightness {
            self.ledBrightness = max(1, min(100, ledBrightness))
        }
        if let bleTxPower = bleTxPower { self.bleTxPower = bleTxPower }

        saveDeviceSettings()
        saveGlobalSettings()
    }

    /// Check if a motion type should trigger alarm
    func shouldTriggerAlarm(for motionType: MotionEventType) -> Bool {
        alarmTriggers.contains(motionType)
    }

    /// Wipes every per-device WatchDog settings key from UserDefaults so the
    /// next `loadDeviceSettings(_:)` call falls back to the defaults coded in
    /// this file. Bonded devices, custom names, notes, and motion logs are
    /// keyed elsewhere and are not touched. All in-memory @Observable
    /// properties are reset to defaults — unconditionally — so views that
    /// observe them update immediately, even when no device page was opened
    /// before this reset (i.e. `currentDeviceID == nil`). For a currently
    /// connected device the defaults are also written back to its
    /// per-device store so the next read matches in-memory state.
    func resetAllDeviceSettingsToDefaults() {
        let ud = UserDefaults.standard
        let bases = [
            armedKey, alarmTypeKey, sensitivityKey, lightsKey, loggingKey,
            disableAlarmWhenConnectedKey, alarmTriggersKey, selectedPresetKey,
            alarmDurationKey, alarmDisabledKey, disconnectSoundDisabledKey,
            ledBrightnessKey, bleTxPowerKey
        ]
        for key in ud.dictionaryRepresentation().keys {
            if bases.contains(where: { key.hasSuffix("_\($0)") }) {
                ud.removeObject(forKey: key)
            }
        }

        isArmed = false
        alarmType = .normal
        sensitivity = .medium
        lightsEnabled = true
        loggingEnabled = false
        disableAlarmWhenConnected = false
        alarmTriggers = [.shaken, .impact, .freefall, .tilted, .doorOpening, .doorClosing]
        selectedPresetRawValue = "maxSecurity"
        alarmDuration = 2
        alarmDisabled = false
        disconnectSoundDisabled = false
        ledBrightness = 100
        bleTxPower = .highPower
        highPerformanceMode = devModeUnlocked

        if currentDeviceID != nil {
            saveDeviceSettings()
        }
    }

    // MARK: - Demo Mode

    /// Snapshots the current observable state, then resets the user-facing
    /// device settings (alarm, sensitivity, LED, etc.) to defaults so the demo
    /// starts clean. Persistence is suppressed for the lifetime of demo mode
    /// — every save in this manager guards on `isDemoMode`. The dev-mode
    /// flags (`debugModeEnabled`, `devModeUnlocked`, `highPerformanceMode`,
    /// `dataLoggingMode`) are preserved unchanged so a power user who entered
    /// demo with dev mode on still sees the debug overlay during the demo.
    func enterDemoMode(deviceID: UUID) {
        guard !isDemoMode else { return }
        demoSnapshot = DemoSnapshot(
            currentDeviceID: currentDeviceID,
            isArmed: isArmed,
            alarmType: alarmType,
            sensitivity: sensitivity,
            lightsEnabled: lightsEnabled,
            loggingEnabled: loggingEnabled,
            disableAlarmWhenConnected: disableAlarmWhenConnected,
            deviceName: deviceName,
            debugModeEnabled: debugModeEnabled,
            highPerformanceMode: highPerformanceMode,
            liveOrientationEnabled: liveOrientationEnabled,
            devModeUnlocked: devModeUnlocked,
            dataLoggingMode: dataLoggingMode,
            alarmTriggers: alarmTriggers,
            selectedPresetRawValue: selectedPresetRawValue,
            alarmDuration: alarmDuration,
            alarmDisabled: alarmDisabled,
            disconnectSoundDisabled: disconnectSoundDisabled,
            ledBrightness: ledBrightness,
            bleTxPower: bleTxPower
        )
        isDemoMode = true
        currentDeviceID = deviceID

        isArmed = false
        alarmType = .normal
        sensitivity = .medium
        lightsEnabled = true
        loggingEnabled = false
        disableAlarmWhenConnected = false
        alarmTriggers = [.shaken, .impact, .freefall, .tilted, .doorOpening, .doorClosing]
        selectedPresetRawValue = "maxSecurity"
        alarmDuration = 2
        alarmDisabled = false
        disconnectSoundDisabled = false
        ledBrightness = 100
        bleTxPower = .highPower
    }

    /// Restores every observable property to the value captured at
    /// `enterDemoMode()` and re-enables persistence. Called from
    /// `BluetoothManager.exitDemoMode()` so both managers always flip
    /// together.
    func exitDemoMode() {
        guard isDemoMode, let snap = demoSnapshot else { return }
        isDemoMode = false
        currentDeviceID = snap.currentDeviceID
        isArmed = snap.isArmed
        alarmType = snap.alarmType
        sensitivity = snap.sensitivity
        lightsEnabled = snap.lightsEnabled
        loggingEnabled = snap.loggingEnabled
        disableAlarmWhenConnected = snap.disableAlarmWhenConnected
        deviceName = snap.deviceName
        debugModeEnabled = snap.debugModeEnabled
        highPerformanceMode = snap.highPerformanceMode
        liveOrientationEnabled = snap.liveOrientationEnabled
        devModeUnlocked = snap.devModeUnlocked
        dataLoggingMode = snap.dataLoggingMode
        alarmTriggers = snap.alarmTriggers
        selectedPresetRawValue = snap.selectedPresetRawValue
        alarmDuration = snap.alarmDuration
        alarmDisabled = snap.alarmDisabled
        disconnectSoundDisabled = snap.disconnectSoundDisabled
        ledBrightness = snap.ledBrightness
        bleTxPower = snap.bleTxPower
        demoSnapshot = nil
    }

    /// Drop every per-device and global setting from memory and disk. Used by
    /// the Wipe App Data flow — `resetAllDeviceSettingsToDefaults` only handles
    /// per-device keys and re-loads the current device, both wrong here.
    func clearAll() {
        let ud = UserDefaults.standard
        let bases = [
            armedKey, alarmTypeKey, sensitivityKey, lightsKey, loggingKey,
            disableAlarmWhenConnectedKey, alarmTriggersKey, selectedPresetKey,
            alarmDurationKey, alarmDisabledKey, disconnectSoundDisabledKey,
            ledBrightnessKey, bleTxPowerKey
        ]
        for key in ud.dictionaryRepresentation().keys {
            if bases.contains(where: { key.hasSuffix("_\($0)") }) {
                ud.removeObject(forKey: key)
            }
        }
        ud.removeObject(forKey: deviceNameKey)
        ud.removeObject(forKey: debugModeKey)
        ud.removeObject(forKey: liveOrientationKey)
        ud.removeObject(forKey: devModeUnlockedKey)
        ud.removeObject(forKey: dataLoggingModeKey)

        currentDeviceID = nil
        isArmed = false
        alarmType = .normal
        sensitivity = .medium
        lightsEnabled = true
        loggingEnabled = false
        disableAlarmWhenConnected = false
        deviceName = "WatchDog"
        debugModeEnabled = false
        highPerformanceMode = false
        liveOrientationEnabled = false
        devModeUnlocked = false
        dataLoggingMode = false
        alarmTriggers = [.shaken, .impact, .freefall, .tilted, .doorOpening, .doorClosing]
        selectedPresetRawValue = "maxSecurity"
        alarmDuration = 2
        alarmDisabled = false
        disconnectSoundDisabled = false
        ledBrightness = 100
        bleTxPower = .highPower
    }
}

// MARK: - Extensions for Bit Values

extension AlarmType {
    var bitValue: UInt8 {
        switch self {
        case .none: return 0b00
        case .calm: return 0b01
        case .normal: return 0b10
        case .loud: return 0b11
        }
    }
    
    static func from(bitValue: UInt8) -> AlarmType {
        switch bitValue {
        case 0b00: return .none
        case 0b01: return .calm
        case 0b10: return .normal
        case 0b11: return .loud
        default: return .normal
        }
    }
}

extension SensitivityLevel {
    var bitValue: UInt8 {
        switch self {
        case .low: return 0b00
        case .medium: return 0b01
        case .high: return 0b10
        }
    }
    
    static func from(bitValue: UInt8) -> SensitivityLevel {
        switch bitValue {
        case 0b00: return .low
        case 0b01: return .medium
        case 0b10: return .high
        default: return .medium
        }
    }
}

/// BLE radio TX power. `normal` = 0 dBm, `highPower` = +8 dBm. String raw
/// values are used so the existing `AnimatedSegmentedControl` widget can
/// display the enum; the wire byte uses `bitValue` (0 / 1) to match the
/// firmware enum at `power_management.h::BleTxPower_t`. Firmware ≥ V1.12.11.
enum BleTxPower: String, CaseIterable, LocalizedSegmentLabel {
    case normal    = "Normal"
    case highPower = "HighPower"

    var bitValue: UInt8 {
        switch self {
        case .normal:    return 0
        case .highPower: return 1
        }
    }

    static func from(bitValue: UInt8) -> BleTxPower {
        switch bitValue {
        case 0:  return .normal
        case 1:  return .highPower
        default: return .highPower
        }
    }

    var segmentLabel: String {
        switch self {
        case .normal:    return LocalizationManager.shared.t(.bleTxPowerNormal)
        case .highPower: return LocalizationManager.shared.t(.bleTxPowerHigh)
        }
    }
}
