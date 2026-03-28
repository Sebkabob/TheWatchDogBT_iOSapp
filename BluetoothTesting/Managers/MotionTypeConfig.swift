//
//  MotionTypeConfig.swift
//  BluetoothTesting
//
//  Created by Assistant on 1/13/26.
//

import Foundation

/// Configuration for motion types received from WatchDog
/// Edit this table to change the display names and settings for each motion type
struct MotionTypeConfig {
    
    /// Motion type mapping table — values match MLC/FSM firmware enum
    static let typeTable: [UInt8: (name: String, triggersAlarm: Bool)] = [
        0: (name: "None",      triggersAlarm: false),
        1: (name: "In Motion", triggersAlarm: false),
        2: (name: "Shaken",    triggersAlarm: true),
        3: (name: "Impact",    triggersAlarm: true),
        4: (name: "Free Fall", triggersAlarm: true),
    ]

    /// Convert firmware motion type byte to iOS MotionEventType
    static func convert(firmwareType: UInt8) -> (eventType: MotionEventType, alarmSounded: Bool) {
        guard let config = typeTable[firmwareType] else {
            return (.none, false)
        }
        let eventType = MotionEventType(rawValue: firmwareType) ?? .none
        return (eventType, config.triggersAlarm)
    }

    /// Get display name for a firmware motion type
    static func getDisplayName(for firmwareType: UInt8) -> String {
        return typeTable[firmwareType]?.name ?? "Unknown Motion Type \(firmwareType)"
    }
}
