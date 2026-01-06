//
//  MotionEvent.swift
//  BluetoothTesting
//
//  Created by Assistant on 1/6/26.
//

import Foundation

enum MotionEventType: UInt8, Codable {
    case unknown = 0
    case lightMovement = 1
    case moderateMovement = 2
    case severeMovement = 3
    case tamper = 4
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .lightMovement: return "Light Movement"
        case .moderateMovement: return "Moderate Movement"
        case .severeMovement: return "Severe Movement"
        case .tamper: return "Tamper Detected"
        }
    }
    
    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .lightMovement: return "water.waves"
        case .moderateMovement: return "wind"
        case .severeMovement: return "tornado"
        case .tamper: return "exclamationmark.triangle.fill"
        }
    }
}

struct MotionEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let eventType: MotionEventType
    let alarmSounded: Bool
    
    init(id: UUID = UUID(), timestamp: Date, eventType: MotionEventType, alarmSounded: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.alarmSounded = alarmSounded
    }
    
    /// Decode from 10-byte data structure from WatchDog
    /// Bytes 0-8: Timestamp (9 bytes)
    /// Byte 9: Event type + alarm flag
    static func decode(from data: Data) -> MotionEvent? {
        guard data.count == 10 else {
            print("❌ Invalid motion event data length: \(data.count)")
            return nil
        }
        
        // Extract timestamp (first 9 bytes) - assume milliseconds since epoch
        let timestampData = data.prefix(9)
        var timestampValue: UInt64 = 0
        for (index, byte) in timestampData.enumerated() {
            timestampValue |= UInt64(byte) << (index * 8)
        }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampValue) / 1000.0)
        
        // Extract event type and alarm flag from last byte
        let lastByte = data[9]
        let eventTypeBits = lastByte & 0x7F  // Lower 7 bits for event type
        let alarmSounded = (lastByte & 0x80) != 0  // Bit 7 for alarm flag
        
        let eventType = MotionEventType(rawValue: eventTypeBits) ?? .unknown
        
        return MotionEvent(timestamp: timestamp, eventType: eventType, alarmSounded: alarmSounded)
    }
    
    /// Encode to 10-byte data structure for WatchDog
    func encode() -> Data {
        var data = Data()
        
        // Encode timestamp (9 bytes) - milliseconds since epoch
        let timestampMs = UInt64(timestamp.timeIntervalSince1970 * 1000.0)
        for i in 0..<9 {
            let byte = UInt8((timestampMs >> (i * 8)) & 0xFF)
            data.append(byte)
        }
        
        // Encode event type + alarm flag (1 byte)
        var lastByte = eventType.rawValue & 0x7F
        if alarmSounded {
            lastByte |= 0x80
        }
        data.append(lastByte)
        
        return data
    }
}
