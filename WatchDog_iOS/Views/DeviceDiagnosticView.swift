//
//  DeviceDiagnosticView.swift
//  BluetoothTesting
//
//  On-demand TLV diagnostic snapshot. Polls the device while open so values
//  track live. Striped rows + per-row status indicators (ok/warn/bad/info)
//  for at-a-glance health reads.
//

import SwiftUI

struct DeviceDiagnosticView: View {
    @Environment(\.dismiss) var dismiss
    var bluetoothManager: BluetoothManager

    @State private var report: DiagnosticReport?
    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var shareText: String = ""
    @State private var pollTimer: Timer?

    private let pollInterval: TimeInterval = 1.0

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    reportView(report)
                } else if isFetching {
                    ProgressView("Capturing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if report != nil {
                        Button {
                            shareText = exportText(for: report!)
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [shareText])
            }
        }
        .onAppear {
            if report == nil { fetch() }
            startPolling()
        }
        .onDisappear { stopPolling() }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            fetch()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetch() {
        guard !isFetching else { return }
        isFetching = true
        errorMessage = nil
        bluetoothManager.requestDiagnostic { result in
            DispatchQueue.main.async {
                isFetching = false
                switch result {
                case .success(let r):
                    report = r
                case .failure(let err):
                    errorMessage = (err as? LocalizedError)?.errorDescription
                        ?? "No response from device."
                }
            }
        }
    }

    // MARK: - Report layout

    @ViewBuilder
    private func reportView(_ r: DiagnosticReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                staleHeader(r)
                summaryBanner(r)

                if let s = r.system  { systemCard(s) }
                if let b = r.battery { batteryCard(b) }
                if let l = r.ble     { bleCard(l) }
                if let s = r.sensor  { sensorCard(s) }
                if let p = r.power   { powerCard(p, system: r.system) }
                if let s = r.storage { storageCard(s) }

                rawCard(r)
            }
            .padding()
        }
    }

    private func staleHeader(_ r: DiagnosticReport) -> some View {
        // Updated each time `report` changes (i.e. every poll tick), so it
        // tracks freshness without a separate Timer.publish driving redraws.
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundColor(.green)
            Text("live · 1 Hz")
            Spacer()
            Text("v\(r.formatVersion) · \(r.sections.count) sections")
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }

    /// Top-level red/yellow banner summarising the worst issue across all sections.
    @ViewBuilder
    private func summaryBanner(_ r: DiagnosticReport) -> some View {
        let issues = collectIssues(r)
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("\(issues.count) issue\(issues.count == 1 ? "" : "s") detected")
                        .fontWeight(.semibold)
                }
                ForEach(issues, id: \.self) { issue in
                    Text("• \(issue)").font(.caption)
                }
            }
            .foregroundColor(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red)
            .cornerRadius(8)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text("All systems normal")
            }
            .font(.caption)
            .foregroundColor(.green)
        }
    }

    private func collectIssues(_ r: DiagnosticReport) -> [String] {
        var out: [String] = []
        if let s = r.system {
            if s.resetCauseIsDangerous { out.append("Reset cause: \(s.resetCauseDescription)") }
            let failed = s.failedInitSubsystems
            if !failed.isEmpty { out.append("Init failed: \(failed.joined(separator: ", "))") }
            if s.lastFaultMarker != 0 { out.append("Prior boot ended in HardFault") }
        }
        if let d = r.battery {
            if d.itpor { out.append("Battery gauge reset (ITPOR)") }
            if d.overTemp { out.append("Battery over temperature") }
            if d.underTemp { out.append("Battery under temperature") }
            if d.isCritical { out.append("Battery critical") }
            if !d.batDetected { out.append("Battery not detected") }
            if let stage = d.initFailStage, stage != 0 {
                out.append("Gauge init failed at stage \(stage)")
            }
        }
        if let s = r.storage {
            if s.loyaltyStoreHealthy == 0 { out.append("Loyalty store unhealthy") }
            if s.i2cErrorsSinceBoot   > 0 { out.append("I2C errors: \(s.i2cErrorsSinceBoot)") }
            if s.eepromFailCount      > 0 { out.append("EEPROM failures: \(s.eepromFailCount)") }
            if s.bq27427FailCount     > 0 { out.append("BQ27427 failures: \(s.bq27427FailCount)") }
            if s.lis2dux12FailCount   > 0 { out.append("LIS2DUX12 failures: \(s.lis2dux12FailCount)") }
        }
        return out
    }

    // MARK: - Cards

    private func systemCard(_ s: DiagSystem) -> some View {
        var rows: [DiagRow] = [
            DiagRow(label: "Firmware",       value: s.fwDisplay,        status: .info),
            DiagRow(label: "Uptime",         value: s.uptimeDisplay,    status: .info),
            DiagRow(label: "Boot count",     value: "\(s.bootCount)",   status: .info),
        ]
        let resetStatus: DiagStatus = s.resetCauseIsDangerous ? .bad
            : (s.resetCause == 0 ? .info : .ok)
        rows.append(DiagRow(
            label: "Reset cause",
            value: s.resetCauseDescription + String(format: "  (0x%02X)", s.resetCause),
            status: resetStatus,
            note: s.resetCauseIsDangerous ? "WDG / LOCKUP indicates an abnormal reboot" : nil
        ))

        let initOK = s.failedInitSubsystems.isEmpty
        rows.append(DiagRow(
            label: "Init bitmask",
            value: String(format: "0x%02X", s.initBitmask),
            status: initOK ? .ok : .bad,
            note: initOK ? "all subsystems initialised" : "failed: " + s.failedInitSubsystems.joined(separator: ", ")
        ))
        rows.append(DiagRow(
            label: "Last fault marker",
            value: s.lastFaultMarker == 0 ? "clean" : String(format: "0x%02X", s.lastFaultMarker),
            status: s.lastFaultMarker == 0 ? .ok : .bad,
            note: s.lastFaultMarker == 0 ? nil : "previous boot ended in HardFault"
        ))
        return DiagCard(title: "System", icon: "cpu", rows: rows)
    }

    private func batteryCard(_ d: BatteryDiagnostic) -> some View {
        var rows: [DiagRow] = []

        let socStatus: DiagStatus =
            d.isCritical ? .bad :
            (d.isLow || d.socPercent < 15) ? .warn :
            d.socPercent >= 20 ? .ok : .info
        rows.append(DiagRow(label: "SOC", value: "\(d.socPercent)%", status: socStatus))

        let v = d.voltageV
        let voltageStatus: DiagStatus =
            (v >= 3.0 && v <= 4.3) ? .ok :
            (v >= 2.7 && v <= 4.4) ? .warn : .bad
        rows.append(DiagRow(label: "Voltage", value: String(format: "%.3f V", v), status: voltageStatus))

        rows.append(DiagRow(label: "Current", value: "\(d.currentMA) mA",
                            status: .info,
                            note: d.currentMA < 0 ? "discharging" : d.currentMA > 0 ? "charging" : nil))

        if let p = d.averagePowerMW {
            rows.append(DiagRow(label: "Power", value: "\(p) mW", status: .info))
        }

        let t = d.temperatureC
        let tempStatus: DiagStatus =
            (t >= 0 && t <= 45) ? .ok :
            (t >= -10 && t <= 60) ? .warn : .bad
        rows.append(DiagRow(label: "Temperature",
                            value: String(format: "%.1f °C / %.1f °F", t, d.temperatureF),
                            status: tempStatus))

        rows.append(DiagRow(label: "Remaining", value: "\(d.remainingMAh) mAh", status: .info))
        rows.append(DiagRow(label: "Full charge", value: "\(d.fullChargeMAh) mAh", status: .info))

        rows.append(DiagRow(label: "Charging",
                            value: d.isCharging ? "yes" : "no",
                            status: .info))
        rows.append(DiagRow(label: "Battery detected",
                            value: d.batDetected ? "yes" : "no",
                            status: d.batDetected ? .ok : .bad))
        rows.append(DiagRow(label: "Gauge learned",
                            value: d.gaugeLearned ? "yes" : "no",
                            status: d.gaugeLearned ? .ok : .warn,
                            note: d.gaugeLearned ? nil : "gauge still learning Qmax / resistance"))

        if d.itpor {
            rows.append(DiagRow(label: "ITPOR", value: "set",
                                status: .bad,
                                note: "gauge power-on reset — learning data lost"))
        }
        if d.overTemp {
            rows.append(DiagRow(label: "Over-temp flag", value: "set", status: .bad))
        }
        if d.underTemp {
            rows.append(DiagRow(label: "Under-temp flag", value: "set", status: .bad))
        }
        if d.isCritical {
            rows.append(DiagRow(label: "Critical flag", value: "set", status: .bad))
        }

        rows.append(DiagRow(label: "Flags raw",       value: String(format: "0x%04X", d.flagsRaw),         status: .info))
        rows.append(DiagRow(label: "Control status",  value: String(format: "0x%04X", d.controlStatusRaw), status: .info))
        rows.append(DiagRow(label: "Status bits",     value: String(format: "0x%02X", d.statusBits),       status: .info))

        if let op = d.opConfigRaw {
            let okOpConfig = op == 0x6458
            rows.append(DiagRow(label: "OpConfig",
                                value: String(format: "0x%04X", op),
                                status: okOpConfig ? .ok : .warn,
                                note: okOpConfig ? nil : "expected 0x6458"))
            if d.opConfigSleepEnabled == true {
                rows.append(DiagRow(label: "OpConfig SLEEP", value: "enabled",
                                    status: .bad,
                                    note: "bit 5 — gauge will report stale current readings"))
            }
        }
        if let cap = d.designCapacityMAH {
            rows.append(DiagRow(label: "Design capacity",
                                value: "\(cap) mAh",
                                status: cap == 300 ? .ok : .warn,
                                note: cap == 300 ? nil : "expected 300 mAh"))
        }
        if let tv = d.terminateVoltageMV {
            rows.append(DiagRow(label: "Terminate voltage",
                                value: "\(tv) mV",
                                status: tv == 3000 ? .ok : .warn,
                                note: tv == 3000 ? nil : "expected 3000 mV"))
        }
        if let tr = d.taperRate {
            rows.append(DiagRow(label: "Taper rate",
                                value: "\(tr)",
                                status: tr == 100 ? .ok : .warn,
                                note: tr == 100 ? nil : "expected 100"))
        }
        if let bo = d.boardOffset {
            let badOffset = abs(Int(bo)) > 5
            rows.append(DiagRow(label: "Board offset",
                                value: "\(bo)",
                                status: badOffset ? .bad : .ok,
                                note: badOffset ? "|offset| > 5 indicates calibration corruption" : nil))
        }
        if let db = d.deadbandMA {
            rows.append(DiagRow(label: "Deadband",
                                value: "\(db) mA",
                                status: db == 5 ? .ok : .warn,
                                note: db == 5 ? nil : "expected 5 mA"))
        }
        if let stage = d.initFailStage {
            rows.append(DiagRow(label: "Init fail stage",
                                value: "\(stage) · \(BatteryDiagnostic.describeInitFailStage(stage))",
                                status: stage == 0 ? .ok : .bad))
        }
        if let c = d.initCompleted {
            rows.append(DiagRow(label: "Init completed",
                                value: "\(c)",
                                status: c == 1 ? .ok : .bad))
        }
        if let pr = d.postResetFired {
            rows.append(DiagRow(label: "Post-reset fired",
                                value: "\(pr)",
                                status: pr == 1 ? .ok : .warn))
        }
        if let chem = d.chemIdRead {
            rows.append(DiagRow(label: "chem_id_read",
                                value: String(format: "0x%04X (%u)", chem, chem),
                                status: chem == 0x3230 ? .ok : .warn,
                                note: chem == 0x3230 ? nil : "expected 0x3230"))
        }
        if let calib = d.calibSpareBytes {
            rows.append(DiagRow(label: "Calib spare", value: hex(calib), status: .info))
        }
        rows.append(DiagRow(label: "Payload version", value: "v\(d.version)", status: .info))

        return DiagCard(title: "Battery", icon: "battery.100", rows: rows)
    }

    private func bleCard(_ b: DiagBLE) -> some View {
        var rows: [DiagRow] = []

        let rssiStatus: DiagStatus
        if b.currentRSSIdBm == 0x7F {
            rssiStatus = .info
        } else if b.currentRSSIdBm >= -75 {
            rssiStatus = .ok
        } else if b.currentRSSIdBm >= -90 {
            rssiStatus = .warn
        } else {
            rssiStatus = .bad
        }
        rows.append(DiagRow(label: "RSSI", value: b.rssiDisplay, status: rssiStatus,
                            note: b.currentRSSIdBm == 0x7F ? "not measured this build" : nil))

        rows.append(DiagRow(label: "Connections since boot",
                            value: "\(b.connectionCountSinceBoot)", status: .info))

        let discStatus: DiagStatus
        switch b.lastDisconnectReason {
        case 0x00: discStatus = .ok
        case 0x13, 0x16: discStatus = .info               // user-terminated
        case 0x08, 0x22, 0x3E: discStatus = .warn          // timeouts / failures
        default: discStatus = .info
        }
        rows.append(DiagRow(
            label: "Last disconnect",
            value: b.disconnectReasonDescription + String(format: "  (0x%02X)", b.lastDisconnectReason),
            status: discStatus
        ))

        let mtuStatus: DiagStatus =
            b.mtuNegotiated >= 100 ? .ok :
            b.mtuNegotiated >= 23  ? .info : .warn
        rows.append(DiagRow(label: "MTU", value: "\(b.mtuNegotiated)", status: mtuStatus))

        rows.append(DiagRow(label: "Conn interval", value: b.connIntervalDisplay,
                            status: b.connectionIntervalUnits == 0 ? .info : .info,
                            note: b.connectionIntervalUnits == 0 ? "not measured this build" : nil))

        return DiagCard(title: "BLE Link", icon: "antenna.radiowaves.left.and.right", rows: rows)
    }

    private func sensorCard(_ s: DiagSensor) -> some View {
        var rows: [DiagRow] = []

        let mlcKnown: Set<UInt8> = [0x00, 0x04, 0x08, 0x0C]
        rows.append(DiagRow(label: "MLC state",
                            value: s.mlcStateLabel,
                            status: mlcKnown.contains(s.cachedMlcState) ? .ok : .warn))
        rows.append(DiagRow(label: "Last FSM event",
                            value: s.lastFsmEvent == 0 ? "—" : String(format: "0x%02X", s.lastFsmEvent),
                            status: .info))
        rows.append(DiagRow(label: "MLC transitions",
                            value: "\(s.mlcTransitionsSinceBoot)",
                            status: .info,
                            note: s.mlcTransitionsSinceBoot == 0 ? "if zero after motion, UCF didn't load" : nil))
        rows.append(DiagRow(label: "INT1 fires", value: "\(s.int1FiresSinceBoot)", status: .info))
        rows.append(DiagRow(label: "Motion events logged",
                            value: "\(s.motionEventsLoggedSinceBoot)", status: .info))

        return DiagCard(title: "Sensor", icon: "gyroscope", rows: rows)
    }

    private func powerCard(_ p: DiagPower, system: DiagSystem?) -> some View {
        var rows: [DiagRow] = []
        rows.append(DiagRow(label: "State", value: p.powerStateLabel, status: .info))
        rows.append(DiagRow(label: "Wakes · motion", value: "\(p.wakesMotion)", status: .info))
        rows.append(DiagRow(label: "Wakes · cable",  value: "\(p.wakesCable)",  status: .info))
        rows.append(DiagRow(label: "Wakes · debug",  value: "\(p.wakesDebug)",  status: .info))
        rows.append(DiagRow(label: "Wakes · tick",   value: "\(p.wakesTick)",   status: .info))
        rows.append(DiagRow(label: "Time in LP",     value: formatSeconds(p.timeInLPSeconds), status: .info))

        if let sys = system,
           let duty = p.sleepDuty(uptimeSeconds: sys.uptimeSeconds) {
            let dutyStatus: DiagStatus =
                duty >= 0.9 ? .ok :
                duty >= 0.5 ? .warn : .bad
            rows.append(DiagRow(label: "Sleep duty",
                                value: String(format: "%.1f%%", duty * 100.0),
                                status: dutyStatus,
                                note: duty < 0.5 ? "device awake more than expected — battery drain risk" : nil))
        }

        return DiagCard(title: "Power", icon: "bolt.fill", rows: rows)
    }

    private func storageCard(_ s: DiagStorage) -> some View {
        var rows: [DiagRow] = []

        let logFraction = s.motionLogMax > 0
            ? Double(s.motionLogCount) / Double(s.motionLogMax)
            : 0
        let logStatus: DiagStatus =
            logFraction >= 0.95 ? .bad :
            logFraction >= 0.80 ? .warn : .ok
        rows.append(DiagRow(label: "Motion log",
                            value: "\(s.motionLogCount) / \(s.motionLogMax)",
                            status: logStatus,
                            note: logFraction >= 0.80 ? "buffer near capacity — sync soon" : nil))

        rows.append(DiagRow(label: "Loyalty store healthy",
                            value: s.loyaltyStoreHealthy == 1 ? "yes" : "no",
                            status: s.loyaltyStoreHealthy == 1 ? .ok : .bad,
                            note: s.loyaltyStoreHealthy == 0 ? "all loyalty operations refused" : nil))

        rows.append(DiagRow(label: "Loyalty claimed",
                            value: s.loyaltyClaimed == 1 ? "yes" : "no",
                            status: s.loyaltyClaimed == 1 ? .ok : .info))

        rows.append(DiagRow(label: "I2C errors",
                            value: "\(s.i2cErrorsSinceBoot)",
                            status: s.i2cErrorsSinceBoot == 0 ? .ok : .bad))
        rows.append(DiagRow(label: "EEPROM fails",
                            value: "\(s.eepromFailCount)",
                            status: s.eepromFailCount == 0 ? .ok : .bad))
        rows.append(DiagRow(label: "BQ27427 fails",
                            value: "\(s.bq27427FailCount)",
                            status: s.bq27427FailCount == 0 ? .ok : .bad))
        rows.append(DiagRow(label: "LIS2DUX12 fails",
                            value: "\(s.lis2dux12FailCount)",
                            status: s.lis2dux12FailCount == 0 ? .ok : .bad))

        return DiagCard(title: "Storage", icon: "internaldrive", rows: rows)
    }

    private func rawCard(_ r: DiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text")
                Text("Raw").font(.headline)
                Spacer()
                Text("\(r.raw.count) bytes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(r.rawHexString)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.systemGray5))
                .cornerRadius(6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .cornerRadius(10)
    }

    // MARK: - Helpers

    private func hex(_ d: Data) -> String {
        d.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func formatSeconds(_ s: UInt32) -> String {
        let total = Int(s)
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60, sec = total % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    // MARK: - Export

    private func exportText(for r: DiagnosticReport) -> String {
        var out = "WatchDog Diagnostics\n"
        out += "captured: \(r.capturedAt)\n"
        out += "format: v\(r.formatVersion), sections: \(r.sections.count)\n\n"
        out += "RAW: \(r.rawHexString)\n\n"

        let issues = collectIssues(r)
        if issues.isEmpty {
            out += "Status: OK (all systems normal)\n\n"
        } else {
            out += "Status: \(issues.count) issue(s):\n"
            for i in issues { out += "  - \(i)\n" }
            out += "\n"
        }

        if let s = r.system {
            out += "[SYSTEM]\n"
            out += "fw=\(s.fwDisplay) uptime=\(s.uptimeDisplay) boot=\(s.bootCount)\n"
            out += String(format: "reset_cause=0x%02X (%@)\n", s.resetCause, s.resetCauseDescription)
            out += String(format: "init_bitmask=0x%02X\n", s.initBitmask)
            if !s.failedInitSubsystems.isEmpty {
                out += "init_failed: " + s.failedInitSubsystems.joined(separator: ", ") + "\n"
            }
            out += String(format: "last_fault=0x%02X\n\n", s.lastFaultMarker)
        }
        if let d = r.battery {
            out += "[BATTERY]\n"
            out += "soc=\(d.socPercent)% v=\(String(format: "%.3f", d.voltageV))V "
                + "i=\(d.currentMA)mA t=\(String(format: "%.1f", d.temperatureC))°C\n"
            out += "remain=\(d.remainingMAh)mAh full=\(d.fullChargeMAh)mAh "
                + "learned=\(d.gaugeLearned)\n"
            out += String(format: "flags=0x%04X ctrl=0x%04X status=0x%02X\n\n",
                          d.flagsRaw, d.controlStatusRaw, d.statusBits)
        }
        if let b = r.ble {
            out += "[BLE]\n"
            out += "rssi=\(b.rssiDisplay) conns=\(b.connectionCountSinceBoot) "
                + "mtu=\(b.mtuNegotiated) interval=\(b.connIntervalDisplay)\n"
            out += String(format: "last_disc=0x%02X (%@)\n\n",
                          b.lastDisconnectReason, b.disconnectReasonDescription)
        }
        if let s = r.sensor {
            out += "[SENSOR]\n"
            out += "mlc=\(s.mlcStateLabel) "
                + "trans=\(s.mlcTransitionsSinceBoot) int1=\(s.int1FiresSinceBoot) "
                + "logged=\(s.motionEventsLoggedSinceBoot)\n\n"
        }
        if let p = r.power {
            out += "[POWER]\n"
            out += "state=\(p.powerStateLabel) "
                + "wakes(motion/cable/debug/tick)="
                + "\(p.wakesMotion)/\(p.wakesCable)/\(p.wakesDebug)/\(p.wakesTick) "
                + "lp=\(p.timeInLPSeconds)s\n\n"
        }
        if let s = r.storage {
            out += "[STORAGE]\n"
            out += "motion_log=\(s.motionLogCount)/\(s.motionLogMax) "
                + "loyalty(healthy/claimed)=\(s.loyaltyStoreHealthy)/\(s.loyaltyClaimed)\n"
            out += "fails(i2c/eeprom/bq/lis)="
                + "\(s.i2cErrorsSinceBoot)/\(s.eepromFailCount)/"
                + "\(s.bq27427FailCount)/\(s.lis2dux12FailCount)\n"
        }
        return out
    }
}

// MARK: - Row + status models

enum DiagStatus {
    case ok, warn, bad, info

    var tint: Color {
        switch self {
        case .ok:   return .green
        case .warn: return .orange
        case .bad:  return .red
        case .info: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .ok:   return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad:  return "xmark.octagon.fill"
        case .info: return "circle.fill"
        }
    }

    /// Smaller dot for low-emphasis info rows.
    var isInfo: Bool { if case .info = self { return true } else { return false } }
}

struct DiagRow: Identifiable {
    /// Use the label as the stable identity — labels are unique within a card
    /// and don't change between polls, so SwiftUI can diff rows in place
    /// instead of tearing down the row tree on every refresh.
    var id: String { label }
    let label: String
    let value: String
    var status: DiagStatus = .info
    var note: String? = nil
}

// MARK: - Card container with striped rows

private struct DiagCard: View {
    let title: String
    let icon: String
    let rows: [DiagRow]
    @State private var expanded: Bool = true

    /// Summarised header status: worst of all rows in the card.
    private var headerStatus: DiagStatus {
        if rows.contains(where: { $0.status == .bad })  { return .bad }
        if rows.contains(where: { $0.status == .warn }) { return .warn }
        if rows.contains(where: { $0.status == .ok })   { return .ok }
        return .info
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: icon)
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: headerStatus.symbol)
                        .font(.caption)
                        .foregroundColor(headerStatus.tint)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if expanded {
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    rowView(row, idx: idx)
                }
            }
        }
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .cornerRadius(10)
    }

    private func rowView(_ row: DiagRow, idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: row.status.symbol)
                    .font(row.status.isInfo ? .system(size: 6) : .caption2)
                    .foregroundColor(row.status.tint)
                    .frame(width: 12, alignment: .center)
                Text(row.label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(row.value)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(row.status == .bad ? .red : .primary)
                    .multilineTextAlignment(.trailing)
            }
            if let note = row.note {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(row.status == .bad || row.status == .warn ? row.status.tint : .secondary)
                    .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Finder-style alternating stripes
        .background(idx.isMultiple(of: 2) ? Color(.systemGray6) : Color(.systemBackground))
    }
}

#Preview {
    DeviceDiagnosticView(bluetoothManager: BluetoothManager())
}
