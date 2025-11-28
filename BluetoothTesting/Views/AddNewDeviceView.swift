//
//  AddNewDeviceView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 11/23/24.
//

import SwiftUI

struct AddNewDeviceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var bondManager = BondManager.shared
    @ObservedObject private var nameManager = DeviceNameManager.shared
    
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var bondedDeviceName = ""
    @State private var connectingDeviceID: UUID?
    @State private var pairingCompleted = false
    
    // Naming prompt for new devices
    @State private var showNamingPrompt = false
    @State private var newDeviceName = ""
    @State private var deviceToPair: BluetoothDevice?
    
    // Filter out already bonded devices
    private var availableDevices: [BluetoothDevice] {
        bluetoothManager.discoveredDevices.filter { device in
            !bondManager.isBonded(deviceID: device.id)
        }.sorted { device1, device2 in
            let name1 = nameManager.getDisplayName(deviceID: device1.id, advertisingName: device1.name)
            let name2 = nameManager.getDisplayName(deviceID: device2.id, advertisingName: device2.name)
            return name1 < name2
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Status indicator
                HStack {
                    Circle()
                        .fill(bluetoothManager.isScanning ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(bluetoothManager.isScanning ? "Scanning..." : "Not Scanning")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Device list
                if availableDevices.isEmpty && bluetoothManager.isScanning {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Looking for WatchDogs...")
                            .foregroundColor(.secondary)
                            .padding()
                        Text("Make sure your WatchDog is powered on")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if availableDevices.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No new devices found")
                            .font(.headline)
                        Text("All nearby WatchDogs are already bonded")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else {
                    List(availableDevices) { device in
                        let displayName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
                        NewDeviceRow(
                            device: device,
                            displayName: displayName,
                            isConnecting: connectingDeviceID == device.id
                        ) {
                            handleDeviceTap(device)
                        }
                    }
                }
                
                if !bluetoothManager.isBluetoothReady {
                    Text("Bluetooth is not available")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Add WatchDog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                bluetoothManager.startScanning()
            }
            .onDisappear {
                bluetoothManager.stopScanning()
            }
            .onChange(of: bluetoothManager.connectedDevice) { connectedDevice in
                // Add bond IMMEDIATELY when connection succeeds
                if let deviceID = connectingDeviceID,
                   let connected = connectedDevice,
                   connected.id == deviceID,
                   !pairingCompleted {
                    
                    print("✅ Device connected - completing pairing")
                    completePairing(device: connected)
                }
            }
            .alert("WatchDog Added!", isPresented: $showSuccessAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("\(bondedDeviceName) has been bonded and is ready to use.")
            }
            .alert("Pairing Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    connectingDeviceID = nil
                }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showNamingPrompt) {
                NameYourWatchDogSheet(
                    deviceName: $newDeviceName,
                    onSave: {
                        print("💾 User clicked Save in naming sheet")
                        // Set custom name then start pairing
                        if let device = deviceToPair {
                            let trimmedName = newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedName.isEmpty {
                                nameManager.setCustomName(deviceID: device.id, name: trimmedName)
                                bondedDeviceName = trimmedName
                                print("✅ Set custom name: \(trimmedName)")
                            } else {
                                bondedDeviceName = device.name
                            }
                            startPairing(device: device)
                        }
                    },
                    onSkip: {
                        print("⏭️ User clicked Skip in naming sheet")
                        // Don't set custom name, just use BT name and start pairing
                        if let device = deviceToPair {
                            bondedDeviceName = device.name
                            startPairing(device: device)
                        }
                    }
                )
            }
        }
    }
    
    private func handleDeviceTap(_ device: BluetoothDevice) {
        let displayName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
        
        // Check if this device has been named before
        let hasBeenNamedBefore = nameManager.hasCustomName(deviceID: device.id)
        
        if hasBeenNamedBefore {
            // Already named - just pair directly
            print("🔗 Device already named - pairing directly with: \(displayName)")
            bondedDeviceName = displayName
            startPairing(device: device)
        } else {
            // New device - prompt for name FIRST
            print("📝 New device detected - showing naming prompt BEFORE pairing")
            deviceToPair = device
            newDeviceName = device.name  // Pre-fill with BT name
            bondedDeviceName = device.name  // Default to BT name in case they skip
            showNamingPrompt = true
        }
    }
    
    private func startPairing(device: BluetoothDevice) {
        print("🔗 Starting pairing process for: \(bondedDeviceName)")
        connectingDeviceID = device.id
        pairingCompleted = false
        
        // Connect to device
        bluetoothManager.connect(to: device)
    }
    
    private func completePairing(device: BluetoothDevice) {
        guard !pairingCompleted else {
            print("⚠️ Pairing already completed, skipping")
            return
        }
        
        pairingCompleted = true
        print("✅ Pairing complete for: \(device.name)")
        
        // Add bond IMMEDIATELY
        bondManager.addBond(deviceID: device.id, name: device.name)
        
        print("✅ Device added to bond list: \(device.name)")
        print("📋 Total bonded devices: \(bondManager.bondedDevices.count)")
        
        // Clear connecting state
        connectingDeviceID = nil
        deviceToPair = nil
        
        // Show success
        showSuccessAlert = true
        
        print("✅ Successfully bonded and staying connected to \(bondedDeviceName)")
    }
}

struct NewDeviceRow: View {
    let device: BluetoothDevice
    let displayName: String
    let isConnecting: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    SignalStrengthIndicator(rssi: device.rssi)
                }
                
                Text(String(device.id.uuidString.prefix(8)))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .monospaced()
                
                Text(isConnecting ? "Pairing..." : "Tap to pair")
                    .font(.caption)
                    .foregroundColor(isConnecting ? .orange : .blue)
            }
            
            Spacer()
            
            if isConnecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
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
                        let generator = UIImpactFeedbackGenerator(style: .soft)
                        generator.impactOccurred()
                    }
                }
                .onEnded { _ in
                    if !isConnecting {
                        isPressed = false
                        onTap()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .disabled(isConnecting)
    }
}

#Preview {
    AddNewDeviceView(bluetoothManager: BluetoothManager())
}

// MARK: - Name Your WatchDog Sheet
struct NameYourWatchDogSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var deviceName: String
    let onSave: () -> Void
    let onSkip: () -> Void
    
    private let maxNameLength = 16
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "tag.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                // Title
                Text("Name Your WatchDog")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Description
                Text("Give this WatchDog a unique name so you don't mix them up with others.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                // Text field
                VStack(alignment: .leading, spacing: 8) {
                    TextField("WatchDog Name", text: $deviceName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 32)
                        .onChange(of: deviceName) { newValue in
                            if newValue.count > maxNameLength {
                                deviceName = String(newValue.prefix(maxNameLength))
                            }
                        }
                    
                    Text("\(deviceName.count)/\(maxNameLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                        onSave()
                    }) {
                        Text("Save Name & Pair")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        dismiss()
                        onSkip()
                    }) {
                        Text("Skip & Pair Now")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
