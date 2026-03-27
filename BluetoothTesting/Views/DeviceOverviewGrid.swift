//
//  DeviceOverviewGrid.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 3/26/26.
//

import SwiftUI

struct DeviceOverviewGrid: View {
    var bluetoothManager: BluetoothManager
    var devices: [BondedDevice]
    var onSelectDevice: (UUID) -> Void
    var onRemoveDevice: (UUID) -> Void
    var onDismiss: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header with dismiss button
            HStack {
                Text("Your WatchDogs")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(devices) { device in
                        DeviceCardView(
                            device: device,
                            bluetoothManager: bluetoothManager,
                            onTap: { onSelectDevice(device.id) },
                            onRemove: { onRemoveDevice(device.id) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Device Card

struct DeviceCardView: View {
    let device: BondedDevice
    var bluetoothManager: BluetoothManager
    var onTap: () -> Void
    var onRemove: () -> Void

    private let nameManager = DeviceNameManager.shared
    private let iconManager = DeviceIconManager.shared

    private var displayName: String {
        nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
    }

    private var isConnected: Bool {
        bluetoothManager.connectedDevice?.id == device.id
    }

    private var statusColor: Color {
        if !isConnected { return .gray }
        let isArmed = (bluetoothManager.deviceState & 0x01) != 0
        return isArmed ? .red : .green
    }

    private var statusText: String {
        if isConnected {
            return bluetoothManager.deviceStateText
        }
        return device.isInRange ? "In Range" : "Out of Range"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Card content
            VStack(spacing: 12) {
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Image(systemName: iconManager.getDisplayIcon(deviceID: device.id).rawValue)
                    .font(.system(size: 40))
                    .foregroundColor(statusColor)
                    .frame(height: 50)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if isConnected && bluetoothManager.batteryLevel >= 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "battery.50")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("\(bluetoothManager.batteryLevel)%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            // Red minus delete button
            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 26, height: 26)
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                }
            }
            .offset(x: 8, y: -8)
        }
    }
}

#Preview {
    DeviceOverviewGrid(
        bluetoothManager: BluetoothManager(),
        devices: [],
        onSelectDevice: { _ in },
        onRemoveDevice: { _ in },
        onDismiss: { }
    )
}
