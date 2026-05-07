//
//  MotionTypeConfig.swift
//  BluetoothTesting
//
//  Created by Assistant on 1/13/26.
//

import Foundation

/// Configuration for motion types received from WatchDog
/// Uses SettingsManager for user-configurable alarm triggers
struct MotionTypeConfig {

    /// Convert firmware motion type byte to iOS MotionEventType
    /// Alarm trigger is determined by user's alarmTriggers setting
    static func convert(firmwareType: UInt8) -> (eventType: MotionEventType, alarmSounded: Bool) {
        let eventType = MotionEventType(rawValue: firmwareType) ?? .none
        let triggers = SettingsManager.shared.shouldTriggerAlarm(for: eventType)
        return (eventType, triggers)
    }
}
