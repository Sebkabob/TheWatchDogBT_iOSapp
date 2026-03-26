//
//  DevicePageView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 3/20/26.
//

import SwiftUI

struct DevicePageView: View {
    var bluetoothManager: BluetoothManager
    private let settingsManager = SettingsManager.shared
    private let nameManager = DeviceNameManager.shared
    private let bondManager = BondManager.shared
    
    let deviceID: UUID
    
    @State private var isLocked = true
    @State private var holdProgress: CGFloat = 0.0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    
    // Sheets
    @State private var showMotionLogs = false
    
    // Track model visibility with animation
    @State private var showModel = false
    
    // Local "connecting" state — set immediately on button press for instant feedback.
    // Cleared when connection succeeds or fails.
    @State private var isConnectingThisDevice = false
    
    // Debug graph history (last 3 minutes)
    @State private var currentHistory: [(date: Date, value: Double)] = []
    @State private var voltageHistory: [(date: Date, value: Double)] = []
    @State private var socHistory: [(date: Date, value: Double)] = []
    @State private var graphUpdateTimer: Timer?
    @State private var minSOC: Double = 100.0
    @State private var maxSOC: Double = 0.0
    
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    
    // MARK: - Computed Properties
    
    /// Whether THIS device is the currently connected device
    private var isDeviceConnected: Bool {
        bluetoothManager.connectedDevice?.id == deviceID
    }
    
    /// Whether this device is currently seen via BLE advertisements OR is connected.
    /// Connected devices stop advertising, so connected == in range.
    private var isDeviceInRange: Bool {
        if isDeviceConnected { return true }
        if isConnectingThisDevice { return true }
        // Check bond manager for recent advertisement
        if let bond = bondManager.getBond(deviceID: deviceID), bond.isInRange {
            return true
        }
        // Also check discovered devices directly
        return bluetoothManager.discoveredDevices.contains(where: { $0.id == deviceID })
    }
    
    /// Whether the connect button should be enabled
    private var canConnect: Bool {
        if isDeviceConnected { return false }
        if isConnectingThisDevice { return false }
        return isDeviceInRange
    }
    
    /// Display name for the device
    private var displayName: String {
        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            return nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
        }
        if let bond = bondManager.getBond(deviceID: deviceID) {
            return nameManager.getDisplayName(deviceID: deviceID, advertisingName: bond.name)
        }
        return "WatchDog"
    }
    
    private var statusText: String {
        if !isDeviceConnected {
            return "Unknown"
        }
        return bluetoothManager.deviceStateText
    }
    
    private var statusColor: Color {
        if !isDeviceConnected {
            return .gray
        }
        let isArmed = (bluetoothManager.deviceState & 0x01) != 0
        return isArmed ? .red : .green
    }
    
    private var connectionTimeString: String {
        let duration = bluetoothManager.connectionDuration
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: Device State Display at the top - Horizontal Layout
            HStack(alignment: .center, spacing: 0) {
                // Left: Device name
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Center: Connection/Lock state
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    
                    Text(statusText)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(statusColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // Right: Battery indicator
                if isDeviceConnected && bluetoothManager.batteryLevel >= 0 {
                    HStack(spacing: 4) {
                        if bluetoothManager.isCharging {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        
                        Image(systemName: batteryIcon)
                            .foregroundColor(batteryColor)
                        Text("\(bluetoothManager.batteryLevel)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            
            // MARK: 3D Model Section with Debug Info
            ZStack(alignment: .leading) {
                if isDeviceInRange {
                    // Device is in range (connected or just advertising) — show 3D model
                    if showModel {
                        Motion3DView(
                            isLocked: isLocked,
                            bluetoothManager: bluetoothManager,
                            // Only allow settings tap when connected
                            allowSettingsTap: isDeviceConnected,
                            targetDeviceID: deviceID
                        )
                        .frame(maxWidth: .infinity)
                        // Dim the model slightly when not connected to hint it's a preview
                        .opacity(isDeviceConnected ? 1.0 : 0.6)
                        .transition(.opacity)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // Device is NOT in range — show placeholder
                    VStack {
                        Spacer()
                        Text("Device not in range")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
                
                // Debug Info Box - Left side (only when connected and debug enabled)
                if isDeviceConnected && settingsManager.debugModeEnabled {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BATTERY STATS")
                                .font(.system(size: 9))
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "Voltage", value: String(format: "%.3fV", bluetoothManager.debugVoltage))
                                VoltageGraph(history: voltageHistory)
                                    .frame(height: 35)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "Current", value: String(format: "%.0fmA", bluetoothManager.debugCurrentDraw))
                                CurrentGraph(history: currentHistory)
                                    .frame(height: 35)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "SOC", value: "\(bluetoothManager.batteryLevel)%")
                                SOCGraph(history: socHistory, minSOC: minSOC, maxSOC: maxSOC)
                                    .frame(height: 35)
                            }
                            
                            DebugInfoRow(label: "Connected", value: connectionTimeString)
                        }
                        .padding(8)
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(8)
                        .shadow(radius: 3)
                        .frame(width: 110)
                        .padding(.leading, 12)
                        .padding(.bottom, 200)
                        
                        Spacer()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isDeviceInRange)
            .animation(.easeInOut(duration: 1.0), value: showModel)
            .animation(.easeInOut(duration: 0.3), value: isDeviceConnected)
            
            // MARK: Bottom Control Section
            VStack(spacing: 12) {
                // Lock button
                LockButton(
                    isLocked: $isLocked,
                    holdProgress: holdProgress,
                    isDisabled: !isDeviceConnected
                )
                .padding(.horizontal, 20)
                .onLongPressGesture(minimumDuration: 1.0, pressing: { isPressing in
                    if isDeviceConnected {
                        if isPressing {
                            startHolding()
                        } else {
                            stopHolding()
                        }
                    }
                }, perform: {
                    // This fires when the full duration is reached
                    // completeHold() is already called by the fill timer
                })
                
                // Bottom buttons row
                HStack(spacing: 12) {
                    if isDeviceConnected {
                        // Disconnect button (red)
                        Button(action: {
                            disconnectDevice()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Disconnect")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(10)
                        }
                    } else if isConnectingThisDevice {
                        // Connecting state — shown immediately on button press
                        Button(action: { }) {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Connecting...")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                        .disabled(true)
                    } else {
                        // Connect button (green when in range, grey when not)
                        Button(action: {
                            connectDevice()
                        }) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Connect")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canConnect ? Color.green : Color.gray.opacity(0.5))
                            .cornerRadius(10)
                        }
                        .disabled(!canConnect)
                    }
                    
                    // Motion Logs button
                    Button(action: {
                        showMotionLogs = true
                    }) {
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
        .statusBar(hidden: true)
        .sheet(isPresented: $showMotionLogs) {
            NavigationStack {
                MotionLogsView()
            }
        }
        .onAppear {
            isLocked = settingsManager.isArmed
            
            print("🎬 DevicePageView appeared - deviceID=\(deviceID.uuidString.prefix(8)), connected=\(isDeviceConnected), inRange=\(isDeviceInRange)")
            
            // Always try to show model if in range
            updateModelVisibility()
            
            if isDeviceConnected {
                startGraphUpdates()
            }
        }
        .onDisappear {
            stopGraphUpdates()
        }
        .onChange(of: settingsManager.isArmed) { _, newIsArmed in
            if isLocked != newIsArmed {
                isLocked = newIsArmed
            }
        }
        .onChange(of: isDeviceConnected) { _, connected in
            if connected {
                // Connection succeeded — clear the connecting flag
                isConnectingThisDevice = false
                print("🔄 Device connected, fading in model")
                withAnimation(.easeInOut(duration: 1.0)) {
                    showModel = true
                }
                startGraphUpdates()
            } else {
                // Device disconnected
                isConnectingThisDevice = false
                print("📵 Device disconnected")
                updateModelVisibility()
                stopGraphUpdates()
            }
        }
        // Watch for changes in range status to update model
        .onChange(of: bluetoothManager.discoveredDevices.count) { _, _ in
            updateModelVisibility()
        }
        // If the BLE manager's isConnecting goes false and we're still
        // showing connecting state, it means connection failed
        .onChange(of: bluetoothManager.isConnecting) { _, connecting in
            if !connecting && isConnectingThisDevice && !isDeviceConnected {
                // Connection attempt finished without success
                print("⚠️ Connection attempt ended without success")
                isConnectingThisDevice = false
            }
        }
    }
    
    // MARK: - Model Visibility
    
    private func updateModelVisibility() {
        let shouldShow = isDeviceInRange
        if shouldShow && !showModel {
            withAnimation(.easeInOut(duration: 1.0)) {
                showModel = true
            }
        } else if !shouldShow && showModel {
            withAnimation(.easeInOut(duration: 0.5)) {
                showModel = false
            }
        }
    }
    
    // MARK: - Connection Methods
    
    private func connectDevice() {
        guard canConnect else { return }
        
        // Set local connecting state IMMEDIATELY for instant UI feedback
        isConnectingThisDevice = true
        
        // If connected to another device, disconnect first
        if let currentDevice = bluetoothManager.connectedDevice, currentDevice.id != deviceID {
            print("🔌 Disconnecting from \(currentDevice.name) before connecting to new device")
            bluetoothManager.disconnect(from: currentDevice)
            
            // Delay to let disconnect complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.performConnect()
            }
        } else {
            performConnect()
        }
    }
    
    private func performConnect() {
        // Clear the suppress flag so scanning/connection works
        bluetoothManager.suppressAutoReconnect = false
        
        // Find the discovered device and connect
        if let device = bluetoothManager.discoveredDevices.first(where: { $0.id == deviceID }) {
            print("🔌 Connecting to \(device.name)")
            bluetoothManager.connect(to: device)
        } else {
            print("⚠️ Device not found in discovered devices, cannot connect")
            isConnectingThisDevice = false
        }
    }
    
    private func disconnectDevice() {
        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            print("🔌 User disconnecting from \(device.name)")
            // Do NOT set suppressAutoReconnect here — MainAppView.ensureScanningActive()
            // will clear it anyway, and we need scanning to continue so the device
            // shows as "in range" after disconnecting.
            bluetoothManager.disconnect(from: device)
            
            // Explicitly restart scanning after a short delay to ensure
            // advertisements are picked up again immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.bluetoothManager.suppressAutoReconnect = false
                if self.bluetoothManager.isBluetoothReady && !self.bluetoothManager.isScanning {
                    print("🔍 Restarting scan after disconnect")
                    self.bluetoothManager.startBackgroundScanning()
                }
            }
        }
    }
    
    // MARK: - Hold to Lock/Unlock
    
    private func startHolding() {
        guard isDeviceConnected else { return }
        guard !isHolding else { return }
        
        isHolding = true
        holdProgress = 0.0
        
        lightHaptic.prepare()
        heavyHaptic.prepare()
        lightHaptic.impactOccurred()
        
        // Drive the fill bar with a repeating timer (~60fps)
        // This avoids relying on withAnimation which can be disrupted by the TabView
        let totalDuration: Double = 1.0
        let interval: Double = 1.0 / 60.0
        let increment: CGFloat = CGFloat(interval / totalDuration)
        
        holdTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if self.isHolding {
                self.holdProgress += increment
                if self.holdProgress >= 1.0 {
                    self.holdProgress = 1.0
                    timer.invalidate()
                    self.holdTimer = nil
                    self.completeHold()
                }
            } else {
                timer.invalidate()
                self.holdTimer = nil
            }
        }
    }
    
    private func stopHolding() {
        guard isHolding else { return }
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    private func completeHold() {
        guard isDeviceConnected else { return }
        
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
    
    // MARK: - Battery
    
    private var batteryIcon: String {
        let level = bluetoothManager.batteryLevel
        if level >= 90 { return "battery.100" }
        if level >= 60 { return "battery.75" }
        if level >= 40 { return "battery.50" }
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
    
    // MARK: - Graph Updates
    
    private func startGraphUpdates() {
        stopGraphUpdates()
        
        updateCurrentHistory(bluetoothManager.debugCurrentDraw)
        updateVoltageHistory(bluetoothManager.debugVoltage)
        updateSOCHistory(Double(bluetoothManager.batteryLevel))
        
        graphUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.updateCurrentHistory(self.bluetoothManager.debugCurrentDraw)
            self.updateVoltageHistory(self.bluetoothManager.debugVoltage)
            self.updateSOCHistory(Double(self.bluetoothManager.batteryLevel))
        }
    }
    
    private func stopGraphUpdates() {
        graphUpdateTimer?.invalidate()
        graphUpdateTimer = nil
        minSOC = 100.0
        maxSOC = 0.0
    }
    
    private func updateCurrentHistory(_ current: Double) {
        let now = Date()
        currentHistory.append((date: now, value: current))
        cleanOldHistory(history: &currentHistory)
    }
    
    private func updateVoltageHistory(_ voltage: Double) {
        let now = Date()
        voltageHistory.append((date: now, value: voltage))
        cleanOldHistory(history: &voltageHistory)
    }
    
    private func updateSOCHistory(_ soc: Double) {
        let now = Date()
        socHistory.append((date: now, value: soc))
        cleanOldHistory(history: &socHistory)
        if soc < minSOC { minSOC = soc }
        if soc > maxSOC { maxSOC = soc }
    }
    
    private func cleanOldHistory(history: inout [(date: Date, value: Double)]) {
        let cutoff = Date().addingTimeInterval(-180)
        history.removeAll { $0.date < cutoff }
    }
}

#Preview {
    DevicePageView(
        bluetoothManager: BluetoothManager(),
        deviceID: UUID()
    )
}
