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
    // 0x03 BLE and 0x05 POWER were removed from the firmware-side dump.
    // The ID gaps are deliberate so a future feature using a new ID can't
    // accidentally collide with stale-firmware-on-newer-app pairings.
    var sensor:  DiagSensor?  { sections[0x04].flatMap(DiagSensor.init) }
    var storage: DiagStorage? { sections[0x06].flatMap(DiagStorage.init) }
    var fault:        DiagFault?        { sections[0x07].flatMap(DiagFault.init) }
    var resetHistory: DiagResetHistory? { sections[0x08].flatMap(DiagResetHistory.init) }

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
        // Use startIndex-relative subscripting so this still works if `data`
        // is a Data slice (e.g. from subdata) with non-zero startIndex.
        let base = data.startIndex
        let version = data[base]
        let count = Int(data[base + 1])
        var sections: [UInt8: Data] = [:]
        var idx = 2
        for _ in 0..<count {
            guard idx + 2 <= data.count else { return nil }
            let id = data[base + idx]; idx += 1
            let len = Int(data[base + idx]); idx += 1
            guard idx + len <= data.count else { return nil }
            sections[id] = data.subdata(in: (base + idx)..<(base + idx + len))
            idx += len
        }
        self.formatVersion = version
        self.capturedAt = Date()
        self.raw = data
        self.sections = sections
    }

    /// Memberwise init used by `merge(_:_:)` to construct a synthetic
    /// merged report from two chunked responses. Not for public use.
    private init(formatVersion: UInt8,
                 capturedAt: Date,
                 raw: Data,
                 sections: [UInt8: Data]) {
        self.formatVersion = formatVersion
        self.capturedAt = capturedAt
        self.raw = raw
        self.sections = sections
    }

    /// Combine the sections from two chunked responses into a single report.
    /// Used by `BluetoothManager.requestDiagnostic` so the iOS UI sees one
    /// merged DiagnosticReport even though the firmware delivered it in
    /// two notifications. On conflicting section IDs, `b` wins (the newer
    /// chunk's value replaces the older — caller controls ordering).
    /// The synthetic `raw` Data is a freshly TLV-encoded blob of the merged
    /// section set, so the "Raw" card and export still render coherently.
    static func merge(_ a: DiagnosticReport, _ b: DiagnosticReport) -> DiagnosticReport {
        var combined = a.sections
        for (id, payload) in b.sections {
            combined[id] = payload
        }
        // Re-serialize raw bytes. Order doesn't matter for the parser but a
        // stable section-id sort makes the hex blob diff-friendly.
        var raw = Data([a.formatVersion, UInt8(combined.count)])
        for id in combined.keys.sorted() {
            let payload = combined[id]!
            raw.append(id)
            raw.append(UInt8(payload.count))
            raw.append(payload)
        }
        return DiagnosticReport(formatVersion: a.formatVersion,
                                capturedAt: Date(),
                                raw: raw,
                                sections: combined)
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

// MARK: - 0x04 SENSOR

struct DiagSensor {
    let cachedMlcState: UInt8
    let lastFsmEvent: UInt8
    let mlcTransitionsSinceBoot: UInt32
    let int1FiresSinceBoot: UInt32
    let motionEventsLoggedSinceBoot: UInt32
    // Appended by firmware that gates MLC alarms behind a 200–600 ms
    // validation window. Nil on older firmware that omits the field.
    let validationsDismissedSinceBoot: UInt16?

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
        validationsDismissedSinceBoot = d.u16(14)
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

// MARK: - 0x07 FAULT

/// Last hard-fault snapshot, captured by HardFault_Handler on the firmware
/// side and persisted to EEPROM. `valid == 0` means no fault has ever been
/// recorded since the EEPROM was wiped — render the whole section as
/// "None recorded" in that case.
struct DiagFault {
    let valid: UInt8
    let schemaVersion: UInt8
    let pc: UInt32        // stacked PC at fault (the offending instruction)
    let lr: UInt32        // stacked LR (typically the return address into caller)
    let xpsr: UInt32      // stacked xPSR (condition flags + IPSR exception #)

    init?(_ d: Data) {
        // Wire layout: valid(1) version(1) reserved(2) pc(4) lr(4) xpsr(4) = 16
        guard let v = d.u8(0),
              let sv = d.u8(1),
              let p = d.u32(4),
              let l = d.u32(8),
              let x = d.u32(12) else { return nil }
        valid = v
        schemaVersion = sv
        pc = p
        lr = l
        xpsr = x
    }

    var isPresent: Bool { valid != 0 }

    var pcHex: String { String(format: "0x%08X", pc) }
    var lrHex: String { String(format: "0x%08X", lr) }
    var xpsrHex: String { String(format: "0x%08X", xpsr) }

    /// Bits 0..8 of xPSR carry the exception number. 0 = thread mode (i.e.
    /// the fault took the CPU from running code — usually what we want);
    /// non-zero means a nested fault, which is worse.
    var exceptionNumber: UInt32 { xpsr & 0x1FF }
}

// MARK: - 0x08 RESET_HISTORY

/// Rolling 8-deep ring of recent reset events. Oldest entry first. Each
/// entry tells us *what kind* of reset happened and *which boot* it ended.
struct DiagResetHistoryEntry: Identifiable {
    let id = UUID()
    let resetCause: UInt8
    let bootCount: UInt32
    let uptimeSecs: UInt32

    /// Same bit layout as DiagSystem.resetCauseFlags.
    var causeLabels: [String] {
        DiagSystem.resetCauseFlags.compactMap {
            (resetCause & (1 << $0.bit)) != 0 ? $0.name : nil
        }
    }

    var causeDescription: String {
        let labels = causeLabels
        if labels.isEmpty { return "clean" }
        return labels.joined(separator: " | ")
    }

    var causeIsDangerous: Bool {
        DiagSystem.resetCauseFlags.contains {
            $0.danger && (resetCause & (1 << $0.bit)) != 0
        }
    }

    /// v1 of the firmware records uptime=0 for every entry because we
    /// don't heartbeat the running uptime to EEPROM. Render "—" when 0.
    var uptimeDisplay: String {
        if uptimeSecs == 0 { return "—" }
        let s = Int(uptimeSecs)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}

struct DiagResetHistory {
    let entries: [DiagResetHistoryEntry]

    init?(_ d: Data) {
        // Wire layout: count(1) + up to 8 × (cause(1) + boot(4) + uptime(4)) = 73
        guard let count = d.u8(0) else { return nil }
        var out: [DiagResetHistoryEntry] = []
        let n = min(Int(count), 8)
        for i in 0..<n {
            let base = 1 + i * 9
            guard let c = d.u8(base),
                  let b = d.u32(base + 1),
                  let u = d.u32(base + 5) else { break }
            out.append(DiagResetHistoryEntry(resetCause: c, bootCount: b, uptimeSecs: u))
        }
        entries = out
    }

    var hasDangerousReset: Bool { entries.contains { $0.causeIsDangerous } }
}
