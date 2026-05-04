//
//  DeviceDiagnosticView.swift
//  BluetoothTesting
//

import SwiftUI

struct DeviceDiagnosticView: View {
    @Environment(\.dismiss) var dismiss
    let snapshot: DiagnosticSnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    row("Loyalty FW Version", String(format: "0x%02X", snapshot.loyaltyFwVersion))
                    row("Bonded Peer Count", "\(snapshot.bondedPeerCount)")
                    row("Adv Mode", snapshot.advMode.displayName)
                    row("Auth Fail Count", "\(snapshot.authFailCount)")
                    row("Pending Unbond", snapshot.pendingUnbond ? "true" : "false")
                    row("Bonded Peer",
                        snapshot.hasBond
                            ? "\(snapshot.bondedPeerAddressString) (\(snapshot.addrTypeDescription))"
                            : "none")

                    Divider().padding(.vertical, 4)

                    Text("Raw")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(snapshot.rawHexString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    DeviceDiagnosticView(
        snapshot: DiagnosticSnapshot(
            data: Data([0xE5, 0x01, 0x01, 0x01, 0x00, 0x00, 0x01, 0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA])
        )!
    )
}
