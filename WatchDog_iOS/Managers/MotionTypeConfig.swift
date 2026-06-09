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
                        wasConnected: Bool) -> (eventType: MotionEventType, alarmSounded: Bool, firedAlarmType: AlarmType?) {
        let eventType = MotionEventType(rawValue: firmwareType) ?? .none
        let settings = SettingsManager.shared

        // The firmware escalates any of {inMotion, shaken, impact,
        // freefall} to ALARM_ACTIVE when the device is armed — the
        // iOS-only `alarmTriggers` per-type set never flowed to the
        // firmware, so honouring it here was misreporting reality.
        // The session-detail event log will now correctly show
        // "alarm fired" for every event that actually rang the
        // buzzer, regardless of whether iOS thought that type was
        // "filterable" via its local set.
        let firmwareFiresOn: Set<MotionEventType> = [.inMotion, .shaken, .impact, .freefall]
        let isAlarmTriggering = firmwareFiresOn.contains(eventType)
        let alarmEnabled = settings.alarmType != .none && !settings.alarmDisabled
        let silencedByConnection = wasConnected && settings.disableAlarmWhenConnected
        let actuallyFires = isAlarmTriggering && alarmEnabled && !silencedByConnection
        // Freeze the current alarm tone on the event so the label can show
        // "Loud alarm fired" / "Calm alarm fired" / "Normal alarm fired".
        // The firmware doesn't echo per-event alarm type over the wire, so
        // iOS reading SettingsManager at processing time is the best signal
        // we have. For drained events this captures the alarm-type *as of
        // reconnect*, which may differ from the type that actually rang —
        // imperfect but better than no information at all.
        let firedAlarmType: AlarmType? = actuallyFires ? settings.alarmType : nil
        return (eventType, actuallyFires, firedAlarmType)
    }
}
