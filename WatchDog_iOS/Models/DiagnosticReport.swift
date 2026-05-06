//
//  DiagnosticReport.swift
//  BluetoothTesting
//
//  Parses the TLV diagnostic blob delivered on the BATTERYDIAG characteristic
//  in response to CMD_REQUEST_DIAG (0xF4). Section parsing is length-driven —
//  unknown section IDs are silently ignored, and trailing bytes inside known
//  sections are also ignored, so firmware can append fields without breaking
//  this app.
//

import Foundation

// MARK: - Top-level

struct DiagnosticReport {
    let formatVersion: UInt8
    let capturedAt: Date
    let raw: Data
    let sections: [UInt8: Data]

    var system:  DiagSystem?  { sections[0x01].flatMap(DiagSystem.init) }
    var battery: BatteryDiagnostic? {
        guard let payload = sections[0x02] else { return nil }
        return BatteryDiagnostic(payload)
    }
    var ble:     DiagBLE?     { sections[0x03].flatMap(DiagBLE.init) }
    var sensor:  DiagSensor?  { sections[0x04].flatMap(DiagSensor.init) }
    var power:   DiagPower?   { sections[0x05].flatMap(DiagPower.init) }
    var storage: DiagStorage? { sections[0x06].flatMap(DiagStorage.init) }

    var rawHexString: String {
        raw.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Heuristic — the new TLV format always starts with format_version=0x01,
    /// section_count >= 1. The legacy auto-pushed BatteryDiagnostic blob has
    /// byte 0 ∈ {2, 3, 11}. They don't collide on byte 0.
    static func looksLikeTLV(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == 0x01 && data[1] >= 1
    }

    init?(_ data: Data) {
        guard data.count >= 2 else { return nil }
        let version = data[0]
        let count = Int(data[1])
        var sections: [UInt8: Data] = [:]
        var idx = 2
        for _ in 0..<count {
            guard idx + 2 <= data.count else { return nil }
            let id = data[idx]; idx += 1
            let len = Int(data[idx]); idx += 1
            guard idx + len <= data.count else { return nil }
            sections[id] = data.subdata(in: idx..<(idx + len))
            idx += len
        }
        self.formatVersion = version
        self.capturedAt = Date()
        self.raw = data
        self.sections = sections
    }
}

// MARK: - Little-endian helpers

private extension Data {
    func u8(_ off: Int)  -> UInt8?  { off < count ? self[startIndex + off] : nil }
    func u16(_ off: Int) -> UInt16? {
        guard off + 1 < count else { return nil }
        return UInt16(self[startIndex + off]) | (UInt16(self[startIndex + off + 1]) << 8)
    }
    func u32(_ off: Int) -> UInt32? {
        guard off + 3 < count else { return nil }
        let b = startIndex
        return UInt32(self[b + off])
            | (UInt32(self[b + off + 1]) << 8)
            | (UInt32(self[b + off + 2]) << 16)
            | (UInt32(self[b + off + 3]) << 24)
    }
    func i8(_ off: Int)  -> Int8?  { u8(off).map  { Int8(bitPattern: $0)  } }
}

// MARK: - 0x01 SYSTEM

struct DiagSystem {
    let uptimeSeconds: UInt32
    let bootCount: UInt32
    let resetCause: UInt8
    let fwMajor: UInt8
    let fwMain: UInt8
    let fwV2: UInt8
    let initBitmask: UInt8
    let lastFaultMarker: UInt8

    init?(_ d: Data) {
        guard let u = d.u32(0),
              let b = d.u32(4),
              let rc = d.u8(8),
              let fM = d.u8(9),
              let fm = d.u8(10),
              let fv = d.u8(11),
              let im = d.u8(12),
              let lf = d.u8(13) else { return nil }
        uptimeSeconds = u
        bootCount = b
        resetCause = rc
        fwMajor = fM
        fwMain = fm
        fwV2 = fv
        initBitmask = im
        lastFaultMarker = lf
    }

    static let initBitNames: [(bit: UInt8, name: String)] = [
        (0, "I2C"),
        (1, "BQ27427"),
        (2, "LIS2DUX12"),
        (3, "EEPROM"),
        (4, "Loyalty"),
        (5, "MotionLogger"),
        (6, "BLE"),
    ]

    /// Names of subsystems whose init bit is 0 (failed / didn't reach end).
    var failedInitSubsystems: [String] {
        Self.initBitNames.compactMap { (initBitmask & (1 << $0.bit)) == 0 ? $0.name : nil }
    }

    static let resetCauseFlags: [(bit: UInt8, name: String, danger: Bool)] = [
        (0, "PAD",    false),
        (1, "POR/BOR", false),
        (2, "SFT",    false),
        (3, "WDG",    true),
        (4, "LOCKUP", true),
    ]

    var resetCauseLabels: [String] {
        Self.resetCauseFlags.compactMap { (resetCause & (1 << $0.bit)) != 0 ? $0.name : nil }
    }

    var resetCauseIsDangerous: Bool {
        Self.resetCauseFlags.contains { $0.danger && (resetCause & (1 << $0.bit)) != 0 }
    }

    var resetCauseDescription: String {
        let labels = resetCauseLabels
        if labels.isEmpty { return "none" }
        return labels.joined(separator: " | ")
    }

    var fwDisplay: String {
        String(format: "V%d.%d.%02d", fwMajor, fwMain, fwV2)
    }

    var uptimeDisplay: String {
        let s = Int(uptimeSeconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m \(sec)s" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}

// MARK: - 0x03 BLE

struct DiagBLE {
    let currentRSSIdBm: Int8        // 0x7F sentinel = not measured
    let connectionCountSinceBoot: UInt16
    let lastDisconnectReason: UInt8
    let mtuNegotiated: UInt16
    let connectionIntervalUnits: UInt16

    init?(_ d: Data) {
        guard let r = d.i8(0),
              let cc = d.u16(1),
              let dr = d.u8(3),
              let mtu = d.u16(4),
              let ci = d.u16(6) else { return nil }
        currentRSSIdBm = r
        connectionCountSinceBoot = cc
        lastDisconnectReason = dr
        mtuNegotiated = mtu
        connectionIntervalUnits = ci
    }

    var rssiDisplay: String {
        currentRSSIdBm == 0x7F ? "—" : "\(currentRSSIdBm) dBm"
    }

    var connIntervalDisplay: String {
        if connectionIntervalUnits == 0 { return "—" }
        let ms = Double(connectionIntervalUnits) * 1.25
        return String(format: "%.2f ms", ms)
    }

    var disconnectReasonDescription: String {
        switch lastDisconnectReason {
        case 0x00: return "none"
        case 0x08: return "supervision timeout"
        case 0x13: return "remote user terminated"
        case 0x16: return "local host terminated"
        case 0x22: return "LL response timeout"
        case 0x3E: return "failed to establish"
        default:   return String(format: "0x%02X", lastDisconnectReason)
        }
    }
}

// MARK: - 0x04 SENSOR

struct DiagSensor {
    let cachedMlcState: UInt8
    let lastFsmEvent: UInt8
    let mlcTransitionsSinceBoot: UInt32
    let int1FiresSinceBoot: UInt32
    let motionEventsLoggedSinceBoot: UInt32

    init?(_ d: Data) {
        guard let m = d.u8(0),
              let f = d.u8(1),
              let t = d.u32(2),
              let i = d.u32(6),
              let me = d.u32(10) else { return nil }
        cachedMlcState = m
        lastFsmEvent = f
        mlcTransitionsSinceBoot = t
        int1FiresSinceBoot = i
        motionEventsLoggedSinceBoot = me
    }

    var mlcStateLabel: String {
        switch cachedMlcState {
        case 0x00: return "STATIONARY_UPRIGHT"
        case 0x04: return "STATIONARY_NOT_UPRIGHT"
        case 0x08: return "IN_MOTION"
        case 0x0C: return "SHAKEN"
        default:   return String(format: "unknown (0x%02X)", cachedMlcState)
        }
    }
}

// MARK: - 0x05 POWER

struct DiagPower {
    let wakesMotion: UInt32
    let wakesCable: UInt32
    let wakesDebug: UInt32
    let wakesTick: UInt32
    let timeInLPSeconds: UInt32
    let currentPowerState: UInt8

    init?(_ d: Data) {
        guard let m = d.u32(0),
              let c = d.u32(4),
              let dbg = d.u32(8),
              let t = d.u32(12),
              let lp = d.u32(16),
              let st = d.u8(20) else { return nil }
        wakesMotion = m
        wakesCable = c
        wakesDebug = dbg
        wakesTick = t
        timeInLPSeconds = lp
        currentPowerState = st
    }

    var powerStateLabel: String {
        switch currentPowerState {
        case 0: return "active"
        case 1: return "LP_IDLE"
        case 2: return "LP_ARMED"
        default: return String(format: "unknown (0x%02X)", currentPowerState)
        }
    }

    /// % of uptime spent asleep, given system.uptimeSeconds. Nil if uptime is 0.
    func sleepDuty(uptimeSeconds: UInt32) -> Double? {
        guard uptimeSeconds > 0 else { return nil }
        return Double(timeInLPSeconds) / Double(uptimeSeconds)
    }
}

// MARK: - 0x06 STORAGE

struct DiagStorage {
    let motionLogCount: UInt16
    let motionLogMax: UInt16
    let loyaltyStoreHealthy: UInt8
    let loyaltyClaimed: UInt8
    let i2cErrorsSinceBoot: UInt32
    let eepromFailCount: UInt32
    let bq27427FailCount: UInt32
    let lis2dux12FailCount: UInt32

    init?(_ d: Data) {
        guard let mc = d.u16(0),
              let mm = d.u16(2),
              let lh = d.u8(4),
              let lc = d.u8(5),
              let i2c = d.u32(6),
              let ee = d.u32(10),
              let bq = d.u32(14),
              let lis = d.u32(18) else { return nil }
        motionLogCount = mc
        motionLogMax = mm
        loyaltyStoreHealthy = lh
        loyaltyClaimed = lc
        i2cErrorsSinceBoot = i2c
        eepromFailCount = ee
        bq27427FailCount = bq
        lis2dux12FailCount = lis
    }

    var hasErrorCounter: Bool {
        i2cErrorsSinceBoot > 0
            || eepromFailCount > 0
            || bq27427FailCount > 0
            || lis2dux12FailCount > 0
    }
}
