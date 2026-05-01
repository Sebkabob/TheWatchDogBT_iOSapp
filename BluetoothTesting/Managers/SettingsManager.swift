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

    // UserDefaults keys — per-device settings
    private let armedKey = "watchdog_armed"
    private let alarmTypeKey = "watchdog_alarm_type"
    private let sensitivityKey = "watchdog_sensitivity"
    private let lightsKey = "watchdog_lights"
    private let loggingKey = "watchdog_logging"
    private let disableAlarmWhenConnectedKey = "watchdog_disable_alarm_connected"
    private let highPerformanceModeKey = "watchdog_high_performance_mode"
    private let alarmTriggersKey = "watchdog_alarm_triggers"
    private let selectedPresetKey = "watchdog_selected_preset"

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
    func encodeDeviceInfo() -> UInt8 {
        var byte: UInt8 = 0
        if highPerformanceMode {
            byte |= (1 << 0)
        }
        return byte
    }

    /// Decodes deviceInfo byte from WatchDog
    func decodeDeviceInfo(from byte: UInt8) {
        highPerformanceMode = (byte & (1 << 0)) != 0
        print("  High Performance Mode: \(highPerformanceMode)")
        saveDeviceSettings()
    }

    /// Decodes a byte from WatchDog into settings
    func decodeSettings(from byte: UInt8) {
        print("📥 Decoding settings byte: 0x\(String(format: "%02X", byte))")
        
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
        
        print("  Armed: \(isArmed)")
        print("  Alarm: \(alarmType.rawValue)")
        print("  Sensitivity: \(sensitivity.rawValue)")
        print("  Lights: \(lightsEnabled)")
        print("  Logging: \(loggingEnabled)")
        print("  Disable Alarm When Connected: \(disableAlarmWhenConnected)")
        
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
    }

    private func saveDeviceSettings() {
        guard let deviceID = currentDeviceID else { return }
        let ud = UserDefaults.standard

        ud.set(isArmed, forKey: deviceKey(armedKey, deviceID))
        ud.set(alarmType.rawValue, forKey: deviceKey(alarmTypeKey, deviceID))
        ud.set(sensitivity.rawValue, forKey: deviceKey(sensitivityKey, deviceID))
        ud.set(lightsEnabled, forKey: deviceKey(lightsKey, deviceID))
        ud.set(loggingEnabled, forKey: deviceKey(loggingKey, deviceID))
        ud.set(disableAlarmWhenConnected, forKey: deviceKey(disableAlarmWhenConnectedKey, deviceID))
        ud.set(highPerformanceMode, forKey: deviceKey(highPerformanceModeKey, deviceID))
        ud.set(alarmTriggers.map { $0.rawValue }, forKey: deviceKey(alarmTriggersKey, deviceID))
        ud.set(selectedPresetRawValue, forKey: deviceKey(selectedPresetKey, deviceID))
    }

    // MARK: - Global Persistence

    private func saveGlobalSettings() {
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
                       preset: String? = nil) {
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

        saveDeviceSettings()
        saveGlobalSettings()
    }

    /// Check if a motion type should trigger alarm
    func shouldTriggerAlarm(for motionType: MotionEventType) -> Bool {
        alarmTriggers.contains(motionType)
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
