//
//  DeviceRow.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct DeviceRow: View {
    let device: BluetoothDevice
    let onTap: () -> Void
    @State private var isPressed = false
    @State private var isConnecting = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Signal strength bars next to name
                    SignalStrengthIndicator(rssi: device.rssi)
                }
                
                // Show device UUID for identification
                Text(String(device.id.uuidString.prefix(8)))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .monospaced()
                
                Text(isConnecting ? "Connecting..." : "Tap to connect")
                    .font(.caption)
                    .foregroundColor(isConnecting ? .orange : .blue)
            }
            
            Spacer()
            
            if isConnecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(isPressed ? Color.blue.opacity(0.15) : Color(.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && !isConnecting {
                        isPressed = true
                        // Trigger haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .soft)
                        generator.impactOccurred()
                    }
                }
                .onEnded { _ in
                    if !isConnecting {
                        isPressed = false
                        isConnecting = true
                        onTap()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .disabled(isConnecting)
    }
}
