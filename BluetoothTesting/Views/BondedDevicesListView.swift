//
//  BondedDevicesListView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 11/23/24.
//

import SwiftUI

struct BondedDevicesListView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var bondManager = BondManager.shared
    @ObservedObject private var nameManager = DeviceNameManager.shared
    @ObservedObject private var iconManager = DeviceIconManager.shared
    @State private var showAddDevice = false
    @State private var deviceToDelete: BondedDevice?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            ZStack {
                if bondManager.bondedDevices.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        
                        Text("No WatchDogs")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Add your first WatchDog to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: {
                            showAddDevice = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add WatchDog")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .padding(.top, 20)
                    }
                } else {
                    // Device list - sort by display name
                    List {
                        ForEach(bondManager.bondedDevices.sorted(by: { device1, device2 in
                            let name1 = nameManager.getDisplayName(deviceID: device1.id, advertisingName: device1.name)
                            let name2 = nameManager.getDisplayName(deviceID: device2.id, advertisingName: device2.name)
                            return name1 < name2
                        })) { device in
                            BondedDeviceRow(
                                device: device,
                                displayName: nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name),
                                displayIcon: iconManager.getDisplayIcon(deviceID: device.id),
                                isConnected: bluetoothManager.connectedDevice?.id == device.id,
                                onTap: {
                                    connectToDevice(device)
                                }
                            )
                        }
                        .onDelete { indexSet in
                            deleteDevices(at: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("My WatchDogs")
            .padding(.top, 10)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddDevice = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddDevice) {
                AddNewDeviceView(bluetoothManager: bluetoothManager)
            }
            .onAppear {
                // Start background scanning to update RSSI
                bluetoothManager.startBackgroundScanning()
            }
            .onDisappear {
                bluetoothManager.stopBackgroundScanning()
            }
            .onChange(of: bluetoothManager.isBluetoothReady) { newValue in
                if newValue && !bluetoothManager.isScanning {
                    print("🔵 Bluetooth ready - starting background scan")
                    bluetoothManager.startBackgroundScanning()
                }
            }
            .alert("Delete WatchDog?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    deviceToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let device = deviceToDelete {
                        forgetDevice(device)
                    }
                }
            } message: {
                if let device = deviceToDelete {
                    let displayName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
                    Text("Are you sure you want to delete \(displayName)? You'll need to pair again to reconnect.")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func deleteDevices(at offsets: IndexSet) {
        let sortedDevices = bondManager.bondedDevices.sorted(by: { device1, device2 in
            let name1 = nameManager.getDisplayName(deviceID: device1.id, advertisingName: device1.name)
            let name2 = nameManager.getDisplayName(deviceID: device2.id, advertisingName: device2.name)
            return name1 < name2
        })
        
        for index in offsets {
            deviceToDelete = sortedDevices[index]
            showDeleteConfirmation = true
        }
    }
    
    private func forgetDevice(_ device: BondedDevice) {
        let displayName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
        print("🗑️ Forgetting device: \(displayName)")
        
        // Disconnect if currently connected
        if bluetoothManager.connectedDevice?.id == device.id,
           let connectedDevice = bluetoothManager.connectedDevice {
            bluetoothManager.disconnect(from: connectedDevice)
        }
        
        // Remove bond (custom name and icon persist intentionally)
        bondManager.removeBond(deviceID: device.id)
        
        deviceToDelete = nil
    }
    
    private func connectToDevice(_ device: BondedDevice) {
        // Find the peripheral in discovered devices
        if let discoveredDevice = bluetoothManager.discoveredDevices.first(where: { $0.id == device.id }) {
            bluetoothManager.connect(to: discoveredDevice)
        } else {
            let displayName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
            print("⚠️ Device not in range: \(displayName)")
            // Could show an alert here
        }
    }
}

struct BondedDeviceRow: View {
    let device: BondedDevice
    let displayName: String
    let displayIcon: DeviceIcon
    let isConnected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    // Get the appropriate icon name based on connection state and fill variant availability
    private var iconName: String {
        // Use .fill variant when connected IF it has one
        if isConnected && displayIcon.hasFillVariant {
            return "\(displayIcon.rawValue).fill"
        }
        return displayIcon.rawValue
    }
    
    // ALL icons change color - green when connected, blue when not
    private var iconColor: Color {
        return isConnected ? .green : .blue
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Device icon - ALL icons change color (green when connected)
            // Icons with .fill also get filled when connected
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if isConnected {
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if device.isInRange {
                    Text("In Range")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("Out of Range")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            // Signal strength or out of range indicator
            if device.isInRange, let rssi = device.currentRSSI {
                SignalStrengthIndicator(rssi: rssi)
            } else {
                OutOfRangeIndicator()
            }
            
            if !isConnected {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isPressed ? Color.blue.opacity(0.1) : Color.clear)
        .onTapGesture {
            if !isConnected {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onTap()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && !isConnected {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

struct OutOfRangeIndicator: View {
    var body: some View {
        ZStack {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 4, height: CGFloat(4 + index * 3))
                }
            }
            .frame(height: 13)
            
            // X overlay
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
        }
    }
}

#Preview {
    BondedDevicesListView(bluetoothManager: BluetoothManager())
}
