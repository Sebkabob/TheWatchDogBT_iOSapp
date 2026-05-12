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

    /// Convert firmware motion type byte to iOS MotionEventType.
    ///
    /// `alarmSounded` reflects whether the alarm *actually* fired for
    /// this event under the user's settings AND the connection context
    /// at the time the event happened. Three suppression conditions
    /// matching the firmware's behaviour:
    ///   1. Per-event-type trigger off (`alarmTriggers` doesn't include
    ///      this type) → no alarm.
    ///   2. Alarm globally disabled (alarmType == `.none` or
    ///      alarmDisabled flag is set) → no alarm.
    ///   3. Silent-when-connected on AND the event happened while
    ///      iOS was connected → firmware suppresses the alarm.
    ///
    /// `wasConnected` tells us which context the event was logged in.
    /// Live motion-alert events are always connected; events arriving
    /// via the drain (post-reconnect) came from the disconnected
    /// period, so they're considered `wasConnected = false`.
    static func convert(firmwareType: UInt8,
                        wasConnected: Bool) -> (eventType: MotionEventType, alarmSounded: Bool) {
        let eventType = MotionEventType(rawValue: firmwareType) ?? .none
        let settings = SettingsManager.shared
        let triggers = settings.shouldTriggerAlarm(for: eventType)
        let alarmEnabled = settings.alarmType != .none && !settings.alarmDisabled
        let silencedByConnection = wasConnected && settings.disableAlarmWhenConnected
        let actuallyFires = triggers && alarmEnabled && !silencedByConnection
        return (eventType, actuallyFires)
    }
}
