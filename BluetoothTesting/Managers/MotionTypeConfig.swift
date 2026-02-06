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
    
    /// Motion type mapping table - EDIT THESE VALUES
    static let typeTable: [UInt8: (name: String, triggersAlarm: Bool)] = [
        0: (name: "Unknown", triggersAlarm: false),
        1: (name: "Small Motion", triggersAlarm: false),
        2: (name: "Medium Motion", triggersAlarm: false),
        3: (name: "Large Motion", triggersAlarm: true),
        4: (name: "Severe Motion", triggersAlarm: true),
        5: (name: "Tamper Detected", triggersAlarm: true),
        // Add more types as needed...
    ]
    
    /// Convert firmware motion type byte to iOS MotionEventType
    static func convert(firmwareType: UInt8) -> (eventType: MotionEventType, alarmSounded: Bool) {
        guard let config = typeTable[firmwareType] else {
            // Unknown type - default to unknown
            return (.unknown, false)
        }
        
        // Map to closest MotionEventType based on name
        let eventType: MotionEventType
        let name = config.name.lowercased()
        
        if name.contains("small") || name.contains("light") {
            eventType = .lightMovement
        } else if name.contains("medium") || name.contains("moderate") {
            eventType = .moderateMovement
        } else if name.contains("large") || name.contains("severe") {
            eventType = .severeMovement
        } else if name.contains("tamper") {
            eventType = .tamper
        } else {
            eventType = .unknown
        }
        
        return (eventType, config.triggersAlarm)
    }
    
    /// Get display name for a firmware motion type
    static func getDisplayName(for firmwareType: UInt8) -> String {
        return typeTable[firmwareType]?.name ?? "Unknown Motion Type \(firmwareType)"
    }
}
