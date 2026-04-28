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

    init?(_ data: Data) {
        guard data.count >= 18, data[0] >= 1, data[0] <= 2 else { return nil }
        func u16(_ o: Int) -> UInt16 { UInt16(data[o]) | (UInt16(data[o+1]) << 8) }
        func i16(_ o: Int) -> Int16  { Int16(bitPattern: u16(o)) }
        version           = data[0]
        socPercent        = data[1]
        voltageMV         = u16(2)
        currentMA         = i16(4)
        remainingMAh      = u16(6)
        fullChargeMAh     = u16(8)
        temperature0_1K   = i16(10)
        flagsRaw          = u16(12)
        controlStatusRaw  = u16(14)
        statusBits        = data[16]
        socUnfiltered     = data[17]
    }
}
