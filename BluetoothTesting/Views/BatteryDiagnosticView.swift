//
//  BatteryDiagnosticView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 4/27/26.
//

import SwiftUI

struct BatteryDiagnosticView: View {
    var bluetoothManager: BluetoothManager

    @State private var isDraining = false
    @State private var showDrainConfirmation = false

    private var diag: BatteryDiagnostic? { bluetoothManager.batteryDiagnostic }

    private var estimatedTimeRemaining: String? {
        guard let diag, diag.currentMA != 0 else { return nil }
        let absCurrent = abs(Double(diag.currentMA))
        guard absCurrent > 0 else { return nil }
        let hours = Double(diag.remainingMAh) / absCurrent
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    var body: some View {
        Group {
            if let diag {
                VStack(spacing: 0) {
                    // Drain banner
                    if isDraining {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Draining battery — auto-stop at 5% SOC")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let eta = estimatedTimeRemaining {
                                    Text("~\(eta) remaining")
                                        .font(.caption)
                                }
                            }
                            Spacer()
                            Text("\(diag.socPercent)%")
                                .font(.title3)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.red)
                    }

                    List {
                        // Warnings
                        if diag.itpor || diag.isCritical || diag.overTemp || diag.underTemp {
                            Section("Warnings") {
                                if diag.itpor {
                                    warningRow(icon: "exclamationmark.triangle.fill", color: .orange,
                                               title: "Gauge Reset (ITPOR)",
                                               subtitle: "Power-on reset detected — learning data lost")
                                }
                                if diag.isCritical {
                                    warningRow(icon: "battery.0", color: .red,
                                               title: "Critical Battery",
                                               subtitle: "SOC below critical threshold")
                                }
                                if diag.overTemp {
                                    warningRow(icon: "thermometer.sun.fill", color: .red,
                                               title: "Over Temperature",
                                               subtitle: "Battery temperature too high")
                                }
                                if diag.underTemp {
                                    warningRow(icon: "thermometer.snowflake", color: .blue,
                                               title: "Under Temperature",
                                               subtitle: "Battery temperature too low")
                                }
                            }
                        }

                        Section("Battery") {
                            diagRow("SOC", value: "\(diag.socPercent)%")
                            diagRow("Voltage", value: String(format: "%.3f V", diag.voltageV))
                            diagRow("Current", value: "\(diag.currentMA) mA")
                            diagRow("Temperature", value: String(format: "%.1f °C / %.1f °F", diag.temperatureC, diag.temperatureF))
                        }

                        Section("Capacity") {
                            diagRow("Remaining", value: "\(diag.remainingMAh) mAh")
                            diagRow("Full Charge", value: "\(diag.fullChargeMAh) mAh")
                        }

                        Section("Learning Status") {
                            diagRow("Gauge Learned", value: diag.gaugeLearned ? "Yes" : "No",
                                    valueColor: diag.gaugeLearned ? .green : .orange)
                            diagRow("Qmax Updated", value: diag.qmaxLearned ? "Yes" : "No",
                                    valueColor: diag.qmaxLearned ? .green : .secondary)
                            diagRow("Resistance Updated", value: diag.resLearned ? "Yes" : "No",
                                    valueColor: diag.resLearned ? .green : .secondary)
                        }

                        Section("Status") {
                            diagRow("Battery Detected", value: diag.batDetected ? "Yes" : "No",
                                    valueColor: diag.batDetected ? .green : .red)
                            diagRow("Charging", value: diag.isCharging ? "Yes" : "No")
                            diagRow("Full", value: diag.isFull ? "Yes" : "No")
                            diagRow("Low", value: diag.isLow ? "Yes" : "No",
                                    valueColor: diag.isLow ? .orange : .secondary)
                        }

                        Section("Raw Registers") {
                            diagRow("Flags", value: String(format: "0x%04X", diag.flagsRaw))
                            diagRow("Control Status", value: String(format: "0x%04X", diag.controlStatusRaw))
                            diagRow("Status Bits", value: String(format: "0x%02X", diag.statusBits))
                        }
                    }

                    // Drain button pinned at bottom
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            if isDraining {
                                bluetoothManager.sendStopDrain()
                                isDraining = false
                            } else {
                                showDrainConfirmation = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: isDraining ? "stop.fill" : "bolt.fill")
                                Text(isDraining ? "Stop Drain" : "Start Drain")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isDraining ? Color.red : Color.green)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .background(Color(.systemBackground))
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text("Waiting for battery diagnostic data...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .navigationTitle("Gauge Health")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bluetoothManager.batteryDiagnostic?.socPercent) { _, soc in
            if isDraining, let soc, soc <= 5 {
                isDraining = false
            }
        }
        .confirmationDialog(
            "Start Battery Drain?",
            isPresented: $showDrainConfirmation,
            titleVisibility: .visible
        ) {
            Button("Start Drain", role: .destructive) {
                bluetoothManager.sendStartDrain()
                isDraining = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will run the battery down to 5% SOC with a loud 100 Hz buzzer and bright white LED. Place the device somewhere the noise won't bother anyone. The device will auto-stop at 5%.")
        }
    }

    private func diagRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundColor(valueColor)
        }
    }

    private func warningRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        BatteryDiagnosticView(bluetoothManager: BluetoothManager())
    }
}
