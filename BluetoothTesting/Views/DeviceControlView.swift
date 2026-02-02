//
//  DeviceControlView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct DeviceControlView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let deviceID: UUID
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var bondManager = BondManager.shared
    @ObservedObject private var nameManager = DeviceNameManager.shared
    @State private var isLocked = true
    @State private var holdProgress: CGFloat = 0.0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    @State private var showMotionLogs = false
    @State private var lastKnownBatteryLevel: Int = -1
    @State private var model3DOpacity: Double = 0.0
    @Environment(\.dismiss) var dismiss
    
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    
    // Check if this device is currently connected
    private var isConnected: Bool {
        bluetoothManager.connectedDevice?.id == deviceID
    }
    
    // Check if we're ready to show full UI (connected AND have initial state)
    private var isFullyConnected: Bool {
        isConnected && bluetoothManager.hasReceivedInitialState
    }
    
    // Get device from bond manager
    private var bondedDevice: BondedDevice? {
        bondManager.getBond(deviceID: deviceID)
    }
    
    // Get display name for device
    private var displayName: String {
        guard let device = bondedDevice else { return "WatchDog" }
        return nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Device State Display at the top - Horizontal Layout
            HStack(alignment: .center, spacing: 0) {
                // Left: Device name
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                // Center: Status - only show locked/unlocked when fully connected
                HStack(spacing: 8) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 12, height: 12)
                    
                    Text(stateText)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(stateColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // Right: Battery indicator
                if isFullyConnected && bluetoothManager.batteryLevel >= 0 {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon)
                            .foregroundColor(batteryColor)
                        Text("\(bluetoothManager.batteryLevel)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else if !isFullyConnected && lastKnownBatteryLevel >= 0 {
                    // Show grey battery icon WITH percentage when disconnected
                    HStack(spacing: 4) {
                        Image(systemName: batteryIconForLevel(lastKnownBatteryLevel))
                            .foregroundColor(.gray)
                        Text("\(lastKnownBatteryLevel)%")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 5)
            .padding(.bottom, 10)
            
            // 3D Model Section - Only show when fully connected
            if isFullyConnected {
                Spacer()
                Motion3DView(isLocked: isLocked, bluetoothManager: bluetoothManager)
                    .frame(maxWidth: .infinity)
                    .opacity(model3DOpacity)
                Spacer()
            } else {
                Spacer()
            }
            
            // Bottom Control Section - Fixed, not scrollable
            VStack(spacing: 12) {
                // Single Lock/Unlock button
                LockButton(
                    isLocked: $isLocked,
                    holdProgress: holdProgress,
                    isDisabled: !isFullyConnected
                )
                .padding(.horizontal, 20)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isHolding && isFullyConnected {
                                startHolding()
                            }
                        }
                        .onEnded { _ in
                            if isFullyConnected {
                                stopHolding()
                            }
                        }
                )
                .disabled(!isFullyConnected)
                
                // Disconnect/Back and Motion Logs buttons side by side
                HStack(spacing: 12) {
                    // Disconnect or Back button (left, red or gray)
                    Button(action: {
                        if isConnected {
                            // User pressed disconnect - this is intentional
                            if let device = bluetoothManager.connectedDevice {
                                bluetoothManager.disconnect(from: device, intentional: true)
                            }
                        } else {
                            // Back button when disconnected
                            dismiss()
                        }
                    }) {
                        HStack {
                            Image(systemName: isConnected ? "xmark.circle.fill" : "chevron.left.circle.fill")
                            Text(isConnected ? "Disconnect" : "Back")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isConnected ? Color.red.opacity(0.8) : Color.gray.opacity(0.8))
                        .cornerRadius(10)
                    }
                    
                    // Motion Logs button (right, light gray)
                    NavigationLink(destination: MotionLogsView()) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text("Motion Logs")
                        }
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            isLocked = settingsManager.isArmed
            
            // Store last known battery level when appearing
            if bluetoothManager.batteryLevel >= 0 {
                lastKnownBatteryLevel = bluetoothManager.batteryLevel
            }
            
            // Set initial opacity based on connection state
            model3DOpacity = isFullyConnected ? 1.0 : 0.0
            
            // Start fast scanning if not fully connected
            if !isFullyConnected {
                print("🔍 DeviceControlView: Starting fast scan on appear (isConnected: \(isConnected), hasState: \(bluetoothManager.hasReceivedInitialState))")
                bluetoothManager.startFastScanning()
            }
            
            print("🎬 View appeared - initial state: isLocked=\(isLocked), isConnected=\(isConnected), isFullyConnected=\(isFullyConnected)")
        }
        .onDisappear {
            // Stop fast scanning when leaving view
            print("👋 DeviceControlView: Stopping fast scan on disappear")
            bluetoothManager.stopFastScanning()
        }
        .onChange(of: settingsManager.isArmed) {
            if isLocked != settingsManager.isArmed {
                isLocked = settingsManager.isArmed
            }
        }
        .onChange(of: bluetoothManager.batteryLevel) {
            if bluetoothManager.batteryLevel >= 0 {
                lastKnownBatteryLevel = bluetoothManager.batteryLevel
            }
        }
        .onChange(of: isConnected) {
            print("📡 DeviceControlView: isConnected changed to \(isConnected)")
            if !isConnected {
                // Check if disconnect was intentional
                if bluetoothManager.wasDisconnectIntentional {
                    // Intentional disconnect - go back to bonded devices list
                    print("⬅️ Intentional disconnect - returning to bonded devices list")
                    dismiss()
                } else {
                    // Unintentional disconnect - start fast scanning to auto-reconnect
                    print("🔄 Unintentional disconnect - starting fast scan for auto-reconnect")
                    bluetoothManager.startFastScanning()
                }
            } else {
                // Connected - stop fast scanning if fully connected
                if isFullyConnected {
                    print("✅ Fully connected - stopping fast scan")
                    bluetoothManager.stopFastScanning()
                }
            }
        }
        .onChange(of: isFullyConnected) {
            print("📊 DeviceControlView: isFullyConnected changed to \(isFullyConnected)")
            if isFullyConnected {
                // Fade in 3D model
                withAnimation(.easeIn(duration: 0.25)) {
                    model3DOpacity = 1.0
                }
                // Stop fast scanning once fully connected
                print("✅ Fully connected - stopping fast scan")
                bluetoothManager.stopFastScanning()
            } else {
                // Hide 3D model immediately when disconnecting
                model3DOpacity = 0.0
            }
        }
        .onChange(of: bluetoothManager.discoveredDevices) {
            print("📱 DeviceControlView: discoveredDevices changed (count: \(bluetoothManager.discoveredDevices.count))")
            print("   isConnected: \(isConnected), wasDisconnectIntentional: \(bluetoothManager.wasDisconnectIntentional)")
            
            // Auto-reconnect when device is discovered (if not connected and disconnect was unintentional)
            if !isConnected && !bluetoothManager.wasDisconnectIntentional {
                if let device = bluetoothManager.discoveredDevices.first(where: { $0.id == deviceID }) {
                    print("🔌 Auto-reconnecting to \(device.name) [\(device.id.uuidString.prefix(8))]")
                    bluetoothManager.connect(to: device)
                } else {
                    print("⚠️ Target device \(deviceID.uuidString.prefix(8)) not in discovered devices")
                    print("   Available devices: \(bluetoothManager.discoveredDevices.map { $0.id.uuidString.prefix(8) }.joined(separator: ", "))")
                }
            } else {
                print("   Skipping auto-reconnect (already connected or intentional disconnect)")
            }
        }
    }
    
    private var stateColor: Color {
        if !isFullyConnected {
            return .yellow
        }
        let isArmed = (bluetoothManager.deviceState & 0x01) != 0
        return isArmed ? .red : .green
    }
    
    private var stateText: String {
        if !isFullyConnected {
            return "Disconnected"
        }
        return bluetoothManager.deviceStateText
    }
    
    private func startHolding() {
        isHolding = true
        holdProgress = 0.0
        
        lightHaptic.prepare()
        heavyHaptic.prepare()
        lightHaptic.impactOccurred()
        
        withAnimation(.linear(duration: 1.0)) {
            holdProgress = 1.0
        }
        
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            if self.isHolding {
                self.completeHold()
            }
        }
    }
    
    private func stopHolding() {
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    private func completeHold() {
        heavyHaptic.impactOccurred(intensity: 1.0)
        
        settingsManager.updateSettings(armed: !isLocked)
        bluetoothManager.sendSettings()
        isLocked.toggle()
        
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    private var batteryIcon: String {
        batteryIconForLevel(bluetoothManager.batteryLevel >= 0 ? bluetoothManager.batteryLevel : lastKnownBatteryLevel)
    }
    
    private func batteryIconForLevel(_ level: Int) -> String {
        if level == 100 { return "battery.100" }
        if level >= 90 { return "battery.100" }
        if level >= 75 { return "battery.75" }
        if level >= 60 { return "battery.75" }
        if level >= 50 { return "battery.50" }
        if level >= 40 { return "battery.50" }
        if level >= 25 { return "battery.25" }
        if level >= 10 { return "battery.25" }
        if level > 0 { return "battery.0" }
        return "battery.0"
    }

    private var batteryColor: Color {
        let level = bluetoothManager.batteryLevel
        if level >= 20 { return .green }
        if level >= 10 { return .orange }
        return .red
    }
}

#Preview {
    DeviceControlView(bluetoothManager: BluetoothManager(), deviceID: UUID())
}
