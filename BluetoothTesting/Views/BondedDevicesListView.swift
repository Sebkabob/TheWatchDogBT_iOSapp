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
    @State private var isRefreshing = false
    @State private var navigationPath = NavigationPath()
    @State private var connectingDeviceID: UUID?
    
    // Helper to get sorted devices
    private var sortedDevices: [BondedDevice] {
        bondManager.bondedDevices.sorted { device1, device2 in
            let name1 = nameManager.getDisplayName(deviceID: device1.id, advertisingName: device1.name)
            let name2 = nameManager.getDisplayName(deviceID: device2.id, advertisingName: device2.name)
            return name1 < name2
        }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                if bondManager.bondedDevices.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "dog")
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
                        ForEach(sortedDevices) { device in
                            Button(action: {
                                handleDeviceTap(device)
                            }) {
                                BondedDeviceRow(
                                    device: device,
                                    displayName: nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name),
                                    displayIcon: iconManager.getDisplayIcon(deviceID: device.id),
                                    isConnected: bluetoothManager.connectedDevice?.id == device.id
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .onDelete { indexSet in
                            deleteDevices(at: indexSet)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await performRefresh()
                    }
                }
                
                // Connection overlay
                if let deviceID = connectingDeviceID,
                   bluetoothManager.connectedDevice?.id == deviceID && !bluetoothManager.hasReceivedInitialState {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Syncing with WatchDog...")
                            .font(.headline)
                        Text("Sniffing for information...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(32)
                    .background(Color(.systemBackground).opacity(0.95))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
            .navigationDestination(for: UUID.self) { deviceID in
                DeviceControlView(bluetoothManager: bluetoothManager)
            }
            .navigationTitle("My WatchDogs")
            .navigationBarTitleDisplayMode(.inline)
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
                print("🏠 BondedDevicesListView: View appeared")
                // Start background scanning
                if !bluetoothManager.isScanning {
                    print("🔍 BondedDevicesListView: Starting background scan")
                    bluetoothManager.startBackgroundScanning()
                }
            }
            .onDisappear {
                print("👋 BondedDevicesListView: View disappeared")
                bluetoothManager.stopBackgroundScanning()
            }
            .onChange(of: bluetoothManager.isBluetoothReady) { newValue in
                print("🔵 BondedDevicesListView: Bluetooth ready changed to \(newValue)")
                if newValue && !bluetoothManager.isScanning {
                    print("🔍 BondedDevicesListView: Bluetooth ready - starting background scan")
                    bluetoothManager.startBackgroundScanning()
                }
            }
            .onChange(of: bluetoothManager.hasReceivedInitialState) { newValue in
                // Navigate to device control view once we have initial state
                if let deviceID = connectingDeviceID,
                   bluetoothManager.connectedDevice?.id == deviceID,
                   newValue {
                    print("✅ BondedDevicesListView: Got initial state, navigating to device view")
                    navigationPath.append(deviceID)
                    connectingDeviceID = nil
                }
            }
            .alert("Forget WatchDog?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    deviceToDelete = nil
                }
                Button("Forget Device", role: .destructive) {
                    if let device = deviceToDelete {
                        forgetDevice(device)
                    }
                }
            } message: {
                if let device = deviceToDelete {
                    let displayName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
                    Text("Are you sure you want to forget \(displayName)? You'll need to pair again to reconnect.")
                }
            }
        }
    }
    
    private func handleDeviceTap(_ device: BondedDevice) {
        let isConnected = bluetoothManager.connectedDevice?.id == device.id
        
        if isConnected && bluetoothManager.hasReceivedInitialState {
            // Already connected and synced - navigate immediately
            print("➡️ BondedDevicesListView: Device already connected, navigating")
            navigationPath.append(device.id)
        } else if isConnected && !bluetoothManager.hasReceivedInitialState {
            // Connected but waiting for state - show overlay
            print("⏳ BondedDevicesListView: Device connected, waiting for state")
            connectingDeviceID = device.id
        } else {
            // Not connected - try to connect if in range, otherwise navigate to disconnected view
            if let discoveredDevice = bluetoothManager.discoveredDevices.first(where: { $0.id == device.id }) {
                print("🔌 BondedDevicesListView: Connecting to device")
                connectingDeviceID = device.id
                bluetoothManager.connect(to: discoveredDevice)
            } else {
                // Device not in range - navigate to disconnected view (user wants to see motion logs)
                print("📵 BondedDevicesListView: Device not in range, navigating to disconnected view")
                navigationPath.append(device.id)
            }
        }
    }
    
    private func performRefresh() async {
        print("🔄 Pull to refresh triggered")
        
        // Stop and restart background scanning to force RSSI update
        bluetoothManager.stopBackgroundScanning()
        
        // Small delay to ensure clean restart
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        bluetoothManager.startBackgroundScanning()
        
        // Wait a bit for scan results
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("✅ Refresh complete")
    }
    
    private func deleteDevices(at offsets: IndexSet) {
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
}

struct BondedDeviceRow: View {
    let device: BondedDevice
    let displayName: String
    let displayIcon: DeviceIcon
    let isConnected: Bool
    
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
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
