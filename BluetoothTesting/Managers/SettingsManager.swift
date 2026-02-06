//
//  SettingsManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // Published properties for UI binding
    @Published var isArmed: Bool = false
    @Published var alarmType: AlarmType = .normal
    @Published var sensitivity: SensitivityLevel = .medium
    @Published var lightsEnabled: Bool = true
    @Published var loggingEnabled: Bool = false
    @Published var disableAlarmWhenConnected: Bool = false
    @Published var deviceName: String = "WatchDog"
    @Published var debugModeEnabled: Bool = false
    
    // UserDefaults keys
    private let armedKey = "watchdog_armed"
    private let alarmTypeKey = "watchdog_alarm_type"
    private let sensitivityKey = "watchdog_sensitivity"
    private let lightsKey = "watchdog_lights"
    private let loggingKey = "watchdog_logging"
    private let disableAlarmWhenConnectedKey = "watchdog_disable_alarm_connected"
    private let deviceNameKey = "watchdog_device_name"
    private let debugModeKey = "watchdog_debug_mode"
    
    private init() {
        loadSettings()
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
        saveSettings()
    }
    
    // MARK: - Persistence
    
    private func saveSettings() {
        UserDefaults.standard.set(isArmed, forKey: armedKey)
        UserDefaults.standard.set(alarmType.rawValue, forKey: alarmTypeKey)
        UserDefaults.standard.set(sensitivity.rawValue, forKey: sensitivityKey)
        UserDefaults.standard.set(lightsEnabled, forKey: lightsKey)
        UserDefaults.standard.set(loggingEnabled, forKey: loggingKey)
        UserDefaults.standard.set(disableAlarmWhenConnected, forKey: disableAlarmWhenConnectedKey)
        UserDefaults.standard.set(deviceName, forKey: deviceNameKey)
        UserDefaults.standard.set(debugModeEnabled, forKey: debugModeKey)
    }
    
    private func loadSettings() {
        isArmed = UserDefaults.standard.bool(forKey: armedKey)
        lightsEnabled = UserDefaults.standard.bool(forKey: lightsKey)
        loggingEnabled = UserDefaults.standard.bool(forKey: loggingKey)
        disableAlarmWhenConnected = UserDefaults.standard.bool(forKey: disableAlarmWhenConnectedKey)
        deviceName = UserDefaults.standard.string(forKey: deviceNameKey) ?? "WatchDog"
        
        // Debug mode defaults to OFF
        if UserDefaults.standard.object(forKey: debugModeKey) != nil {
            debugModeEnabled = UserDefaults.standard.bool(forKey: debugModeKey)
        } else {
            debugModeEnabled = false
        }
        
        if let alarmString = UserDefaults.standard.string(forKey: alarmTypeKey),
           let alarm = AlarmType(rawValue: alarmString) {
            alarmType = alarm
        }
        
        if let sensString = UserDefaults.standard.string(forKey: sensitivityKey),
           let sens = SensitivityLevel(rawValue: sensString) {
            sensitivity = sens
        }
    }
    
    /// Call this when user manually changes settings
    func updateSettings(name: String? = nil, armed: Bool? = nil, alarm: AlarmType? = nil,
                       sens: SensitivityLevel? = nil, lights: Bool? = nil, logging: Bool? = nil,
                       disableAlarmConnected: Bool? = nil, debugMode: Bool? = nil) {
        if let name = name { deviceName = name }
        if let armed = armed { isArmed = armed }
        if let alarm = alarm { alarmType = alarm }
        if let sens = sens { sensitivity = sens }
        if let lights = lights { lightsEnabled = lights }
        if let logging = logging { loggingEnabled = logging }
        if let disableAlarmConnected = disableAlarmConnected { disableAlarmWhenConnected = disableAlarmConnected }
        if let debugMode = debugMode { debugModeEnabled = debugMode }
        
        saveSettings()
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
