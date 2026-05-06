//
//  MotionEvent.swift
//  BluetoothTesting
//
//  Created by Assistant on 1/6/26.
//

import Foundation

enum MotionEventType: UInt8, Codable {
    case none         = 0
    case inMotion     = 1
    case shaken       = 2
    case impact       = 3
    case freefall     = 4
    case tilted       = 5
    case doorOpening  = 6
    case doorClosing  = 7

    var displayName: String {
        switch self {
        case .none:         return "None"
        case .inMotion:     return "In Motion"
        case .shaken:       return "Shaken"
        case .impact:       return "Impact"
        case .freefall:     return "Free Fall"
        case .tilted:       return "Tilted"
        case .doorOpening:  return "Door Opening"
        case .doorClosing:  return "Door Closing"
        }
    }

    var icon: String {
        switch self {
        case .none:         return "minus.circle"
        case .inMotion:     return "figure.walk"
        case .shaken:       return "waveform.path"
        case .impact:       return "exclamationmark.triangle"
        case .freefall:     return "arrow.down.circle"
        case .tilted:       return "angle"
        case .doorOpening:  return "door.left.hand.open"
        case .doorClosing:  return "door.left.hand.closed"
        }
    }
}

struct MotionEvent: Identifiable, Codable {
    let id: UUID
    let deviceID: UUID
    let timestamp: Date
    let eventType: MotionEventType
    let alarmSounded: Bool

    init(id: UUID = UUID(), deviceID: UUID, timestamp: Date, eventType: MotionEventType, alarmSounded: Bool) {
        self.id = id
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.eventType = eventType
        self.alarmSounded = alarmSounded
    }
}
