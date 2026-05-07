//
//  BatteryDiagnostic.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 4/27/26.
//

import Foundation

struct BatteryDiagnostic {
    let version: UInt8
    let socPercent: UInt8
    let voltageMV: UInt16
    let currentMA: Int16
    let remainingMAh: UInt16
    let fullChargeMAh: UInt16
    let temperature0_1K: Int16
    let flagsRaw: UInt16
    let controlStatusRaw: UInt16
    let statusBits: UInt8
    let socUnfiltered: UInt8

    // v3-only gauge config readback / extended telemetry. Nil on v2 packets.
    let designCapacityMAH: UInt16?
    let terminateVoltageMV: UInt16?
    let taperRate: UInt16?
    let opConfigRaw: UInt16?
    let averagePowerMW: Int16?
    let boardOffset: Int8?
    let deadbandMA: UInt8?

    // v11-only transient diagnostic fields. Nil on v2/v3 packets.
    let ccGainBytes: Data?              // bytes 30..33 — TI 4-byte custom float
    let ccDeltaBytes: Data?             // bytes 34..37 — TI 4-byte custom float
    let ccOffset: Int16?                // bytes 38..39
    let candidateBoardOffset: UInt16?   // bytes 40..41 — silicon-rev dependent
    let calibSpareBytes: Data?          // bytes 42..45
    let initFailStage: UInt8?           // byte 46 — see code table
    let initCompleted: UInt8?           // byte 47
    let postResetFired: UInt8?          // byte 48
    let chemIdRead: UInt16?             // bytes 49..50

    var temperatureC: Double { Double(temperature0_1K) / 10.0 - 273.15 }
    var temperatureF: Double { temperatureC * 9.0 / 5.0 + 32.0 }
    var voltageV: Double { Double(voltageMV) / 1000.0 }
    var isCharging: Bool   { statusBits & (1 << 0) != 0 }
    var isFull: Bool       { statusBits & (1 << 1) != 0 }
    var isLow: Bool        { statusBits & (1 << 2) != 0 }
    var isCritical: Bool   { statusBits & (1 << 3) != 0 }
    var batDetected: Bool  { statusBits & (1 << 4) != 0 }
    var qmaxLearned: Bool  { statusBits & (1 << 5) != 0 }
    var resLearned: Bool   { statusBits & (1 << 6) != 0 }
    var itpor: Bool        { statusBits & (1 << 7) != 0 }
    var gaugeLearned: Bool { qmaxLearned && resLearned }
    var overTemp: Bool     { flagsRaw & (1 << 15) != 0 }
    var underTemp: Bool    { flagsRaw & (1 << 14) != 0 }

    // Bit 5 (0x0020) of OpConfig is SLEEP. Set ⇒ gauge sleeps and reports stale current.
    var opConfigSleepEnabled: Bool? {
        guard let opConfigRaw else { return nil }
        return (opConfigRaw & 0x0020) != 0
    }

    init?(_ data: Data) {
        guard data.count >= 1 else { return nil }
        let v = data[0]

        let requiredLength: Int
        switch v {
        case 2:  requiredLength = 18
        case 3:  requiredLength = 30
        case 11: requiredLength = 51
        default:
            Log.warn(.battery, "Unknown packet version \(v) · dropping (len=\(data.count))")
            return nil
        }
        guard data.count >= requiredLength else {
            Log.warn(.battery, "v\(v) needs \(requiredLength) bytes, got \(data.count)")
            return nil
        }

        let base = data.startIndex
        func u16(_ o: Int) -> UInt16 {
            UInt16(data[base + o]) | (UInt16(data[base + o + 1]) << 8)
        }
        func i16(_ o: Int) -> Int16 { Int16(bitPattern: u16(o)) }

        version          = v
        socPercent       = data[base + 1]
        voltageMV        = u16(2)
        currentMA        = i16(4)
        remainingMAh     = u16(6)
        fullChargeMAh    = u16(8)
        temperature0_1K  = i16(10)
        flagsRaw         = u16(12)
        controlStatusRaw = u16(14)
        statusBits       = data[base + 16]
        socUnfiltered    = data[base + 17]

        if v == 3 || v == 11 {
            designCapacityMAH  = u16(18)
            terminateVoltageMV = u16(20)
            taperRate          = u16(22)
            opConfigRaw        = u16(24)
            averagePowerMW     = i16(26)
            boardOffset        = Int8(bitPattern: data[base + 28])
            deadbandMA         = data[base + 29]
        } else {
            designCapacityMAH  = nil
            terminateVoltageMV = nil
            taperRate          = nil
            opConfigRaw        = nil
            averagePowerMW     = nil
            boardOffset        = nil
            deadbandMA         = nil
        }

        if v == 11 {
            ccGainBytes          = data.subdata(in: (base + 30)..<(base + 34))
            ccDeltaBytes         = data.subdata(in: (base + 34)..<(base + 38))
            ccOffset             = i16(38)
            candidateBoardOffset = u16(40)
            calibSpareBytes      = data.subdata(in: (base + 42)..<(base + 46))
            initFailStage        = data[base + 46]
            initCompleted        = data[base + 47]
            postResetFired       = data[base + 48]
            chemIdRead           = u16(49)
        } else {
            ccGainBytes          = nil
            ccDeltaBytes         = nil
            ccOffset             = nil
            candidateBoardOffset = nil
            calibSpareBytes      = nil
            initFailStage        = nil
            initCompleted        = nil
            postResetFired       = nil
            chemIdRead           = nil
        }
    }

    static func describeInitFailStage(_ stage: UInt8) -> String {
        switch stage {
        case 0:  return "ok / not yet reached"
        case 1:  return "bq27427_init() failed"
        case 2:  return "device_type wrong"
        case 3:  return "initial INITCOMP timeout"
        case 4:  return "post-RESET INITCOMP timeout"
        case 5:  return "enter_config failed"
        case 6:  return "set_current_polarity failed"
        case 7:  return "set_capacity failed"
        case 8:  return "set_design_energy failed"
        case 9:  return "set_terminate_voltage failed"
        case 10: return "set_taper_rate failed"
        case 11: return "disable_sleep failed"
        case 12: return "exit_config failed"
        default: return "unknown (\(stage))"
        }
    }
}
