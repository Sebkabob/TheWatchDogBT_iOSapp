//
//  BondedDevicesListView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 11/23/24.
//

import SwiftUI

struct BondedDevicesListView: View {
    var bluetoothManager: BluetoothManager
    @Binding var navigationPath: NavigationPath
    private let bondManager = BondManager.shared
    private let nameManager = DeviceNameManager.shared
    private let iconManager = DeviceIconManager.shared
    @State private var showAddDevice = false
    @State private var deviceToDelete: BondedDevice?
    @State private var showDeleteConfirmation = false
    @State private var isRefreshing = false
    @State private var connectingDeviceID: UUID?
    
    // Timeout for connection attempt from the list
    @State private var connectionTimeoutTimer: Timer?
    @State private var showConnectionFailed = false
    
    private var sortedDevices: [BondedDevice] {
        bondManager.bondedDevices.sorted { device1, device2 in
            let name1 = nameManager.getDisplayName(deviceID: device1.id, advertisingName: device1.name)
            let name2 = nameManager.getDisplayName(deviceID: device2.id, advertisingName: device2.name)
            return name1 < name2
        }
    }
    
    var body: some View {
        ZStack {
            if bondManager.bondedDevices.isEmpty {
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
                List {
                    ForEach(sortedDevices) { device in
                        Button(action: {
                            handleDeviceTap(device)
                        }) {
                            BondedDeviceRow(
                                device: device,
                                displayName: nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name),
                                displayIcon: iconManager.getDisplayIcon(deviceID: device.id),
                                isConnected: bluetoothManager.connectedDevice?.id == device.id,
                                isConnecting: connectingDeviceID == device.id
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
            
            // Connection overlay — shown IMMEDIATELY when user taps an in-range device
            if let deviceID = connectingDeviceID {
                let displayName = getDisplayNameFor(deviceID: deviceID)
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Syncing with \(displayName)...")
                        .font(.headline)
                    Text("Sniffing for information...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Cancel button in case it takes too long
                    Button("Cancel") {
                        cancelConnection()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                }
                .padding(32)
                .background(Color(.systemBackground).opacity(0.95))
                .cornerRadius(16)
                .shadow(radius: 10)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: connectingDeviceID != nil)
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
        .fullScreenCover(isPresented: $showAddDevice) {
            AddNewDeviceView(
                bluetoothManager: bluetoothManager,
                onPaired: { deviceID in
                    showAddDevice = false
                    navigationPath.append(deviceID)
                },
                onCancel: {
                    showAddDevice = false
                }
            )
        }
        .onAppear {
            print("🏠 BondedDevicesListView: View appeared")
            // Save nav state: we're on the list
            NavigationStateManager.shared.saveDeviceList()
            
            // Clear suppress flag when returning to list
            bluetoothManager.suppressAutoReconnect = false
            
            if !bluetoothManager.isScanning {
                print("🔍 BondedDevicesListView: Starting background scan")
                bluetoothManager.startBackgroundScanning()
            }
        }
        .onDisappear {
            print("👋 BondedDevicesListView: View disappeared")
            bluetoothManager.stopBackgroundScanning()
        }
        .onChange(of: bluetoothManager.isBluetoothReady) { _, newValue in
            print("🔵 BondedDevicesListView: Bluetooth ready changed to \(newValue)")
            if newValue && !bluetoothManager.isScanning {
                print("🔍 BondedDevicesListView: Bluetooth ready - starting background scan")
                bluetoothManager.startBackgroundScanning()
            }
        }
        .onChange(of: bluetoothManager.hasReceivedInitialState) { _, newValue in
            // Navigate to device control view once we have initial state
            // Only if we initiated a connection from this view (connectingDeviceID is set)
            if let deviceID = connectingDeviceID,
               bluetoothManager.connectedDevice?.id == deviceID,
               newValue {
                print("✅ BondedDevicesListView: Got initial state, navigating to device view")
                connectionTimeoutTimer?.invalidate()
                connectionTimeoutTimer = nil
                navigationPath.append(deviceID)
                connectingDeviceID = nil
            }
        }
        .onChange(of: bluetoothManager.connectedDevice) { _, device in
            // If we were waiting for a connection and it failed (device became nil),
            // clear the overlay
            if connectingDeviceID != nil && device == nil {
                // Check if we're still supposed to be connecting
                // (connection dropped before initial state)
                if !bluetoothManager.isConnecting {
                    print("⚠️ Connection lost while waiting for sync")
                    // Don't clear immediately — BLE might retry. Let the timeout handle it.
                }
            }
        }
        .alert("Connection Failed", isPresented: $showConnectionFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not connect to the WatchDog. Make sure it's powered on and in range, then try again.")
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
    
    private func getDisplayNameFor(deviceID: UUID) -> String {
        if let bond = bondManager.getBond(deviceID: deviceID) {
            return nameManager.getDisplayName(deviceID: deviceID, advertisingName: bond.name)
        }
        return "WatchDog"
    }
    
    private func handleDeviceTap(_ device: BondedDevice) {
        // Don't allow tapping while already connecting
        guard connectingDeviceID == nil else {
            print("⚠️ Already connecting to a device, ignoring tap")
            return
        }
        
        let isConnected = bluetoothManager.connectedDevice?.id == device.id
        
        if isConnected && bluetoothManager.hasReceivedInitialState {
            // Already connected and synced - navigate immediately
            print("➡️ BondedDevicesListView: Device already connected, navigating")
            navigationPath.append(device.id)
        } else if isConnected && !bluetoothManager.hasReceivedInitialState {
            // Connected but waiting for state - show overlay immediately
            print("⏳ BondedDevicesListView: Device connected, waiting for state")
            showSyncingOverlay(for: device.id)
        } else {
            // Not connected — check if device is in range
            if let discoveredDevice = bluetoothManager.discoveredDevices.first(where: { $0.id == device.id }) {
                // Device in range — show overlay IMMEDIATELY then connect in background
                print("🔌 BondedDevicesListView: Device in range — showing overlay and connecting")
                showSyncingOverlay(for: device.id)
                bluetoothManager.connect(to: discoveredDevice)
            } else {
                // Device NOT in range - navigate directly to disconnected view
                print("📵 BondedDevicesListView: Device not in range, navigating to disconnected view")
                navigationPath.append(device.id)
            }
        }
    }
    
    private func showSyncingOverlay(for deviceID: UUID) {
        connectingDeviceID = deviceID
        
        // Start a timeout — if we don't get initial state within 15 seconds, cancel
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [self] _ in
            DispatchQueue.main.async {
                if self.connectingDeviceID != nil {
                    print("⏱️ Connection/sync timeout from list view")
                    self.cancelConnection()
                    self.showConnectionFailed = true
                }
            }
        }
    }
    
    private func cancelConnection() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        
        // If we're mid-connection, cancel it
        if let deviceID = connectingDeviceID,
           let device = bluetoothManager.connectedDevice,
           device.id == deviceID {
            bluetoothManager.disconnect(from: device)
        }
        
        connectingDeviceID = nil
        
        // Restart background scanning
        if !bluetoothManager.isScanning {
            bluetoothManager.startBackgroundScanning()
        }
    }
    
    private func performRefresh() async {
        print("🔄 Pull to refresh triggered")
        bluetoothManager.stopBackgroundScanning()
        try? await Task.sleep(nanoseconds: 500_000_000)
        bluetoothManager.startBackgroundScanning()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
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
        
        if bluetoothManager.connectedDevice?.id == device.id,
           let connectedDevice = bluetoothManager.connectedDevice {
            bluetoothManager.disconnect(from: connectedDevice)
        }
        
        bondManager.removeBond(deviceID: device.id)
        deviceToDelete = nil
    }
}

struct BondedDeviceRow: View {
    let device: BondedDevice
    let displayName: String
    let displayIcon: DeviceIcon
    let isConnected: Bool
    var isConnecting: Bool = false
    
    @State private var isPressed = false
    
    private var iconName: String {
        if isConnected && displayIcon.hasFillVariant {
            return "\(displayIcon.rawValue).fill"
        }
        return displayIcon.rawValue
    }
    
    private var iconColor: Color {
        if isConnecting {
            return .orange
        }
        return isConnected ? .green : .blue
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if isConnecting {
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if isConnected {
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
            
            if isConnecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .scaleEffect(0.7)
            } else if device.isInRange, let rssi = device.currentRSSI {
                SignalStrengthIndicator(rssi: rssi)
            } else {
                OutOfRangeIndicator()
            }
            
            if !isConnected && !isConnecting {
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
                    if !isPressed { isPressed = true }
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
            
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
        }
    }
}

#Preview {
    BondedDevicesListView(bluetoothManager: BluetoothManager(), navigationPath: .constant(NavigationPath()))
}
