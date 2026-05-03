//
//  DevicePageView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 3/20/26.
//

import SwiftUI
import SceneKit

struct DevicePageView: View {
    var bluetoothManager: BluetoothManager
    private let settingsManager = SettingsManager.shared
    private let nameManager = DeviceNameManager.shared
    private let bondManager = BondManager.shared
    
    let deviceID: UUID
    var onOverviewRequest: (() -> Void)? = nil
    var onSettingsModeChange: ((Bool) -> Void)? = nil
    var animateEntrance: Bool = false

    @State private var controlsRevealed = true
    @State private var isLocked = true
    @State private var holdProgress: CGFloat = 0.0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    
    // Sheets
    @State private var showMotionLogs = false
    @State private var showBatteryDiag = false
    
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

    // Dev mode tap counter
    @State private var devTapCount: Int = 0
    @State private var devTapResetTask: Task<Void, Never>?
    @State private var devModeToast: String?

    // Data recording
    private let recorder = MotionDataRecorder.shared
    @State private var csvShareURL: URL?
    @State private var showShareSheet = false

    // Diagnostic flow
    @State private var isFetchingDiagnostic = false
    @State private var diagnosticSnapshot: DiagnosticSnapshot?
    @State private var showDiagnostic = false
    @State private var diagnosticErrorMessage: String?

    // Settings mode (model slides right, settings panel fades in on the left)
    @State private var inSettingsMode = false
    @State private var settingsContentVisible = false
    @State private var editableName: String = ""
    @State private var showForgetConfirmation = false
    private let maxNameLength = 16

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Init

    init(bluetoothManager: BluetoothManager, deviceID: UUID, onOverviewRequest: (() -> Void)? = nil, onSettingsModeChange: ((Bool) -> Void)? = nil, animateEntrance: Bool = false) {
        self.bluetoothManager = bluetoothManager
        self.deviceID = deviceID
        self.onOverviewRequest = onOverviewRequest
        self.onSettingsModeChange = onSettingsModeChange
        self.animateEntrance = animateEntrance
        _controlsRevealed = State(initialValue: !animateEntrance)
    }

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
    
    private var isShowingLiveDeviceState: Bool {
        bluetoothManager.connectedDevice?.id == deviceID && bluetoothManager.hasReceivedInitialState
    }

    private var statusText: String {
        if bluetoothManager.mlcState == .stabilizing && isShowingLiveDeviceState {
            return "Locking"
        }
        return isLocked ? "Locked" : "Unlocked"
    }

    private var statusColor: Color {
        if bluetoothManager.mlcState == .stabilizing && isShowingLiveDeviceState {
            return .blue
        }
        return isLocked ? .red : .green
    }

    private var mlcIndicatorVisible: Bool {
        guard isShowingLiveDeviceState else { return false }
        let mlc = bluetoothManager.mlcState
        if mlc == .unknown { return false }
        if mlc == .stationary && !isLocked { return false }
        return true
    }

    private var lockSyncSignal: String {
        let connID = bluetoothManager.connectedDevice?.id.uuidString ?? "-"
        let received = bluetoothManager.hasReceivedInitialState ? "1" : "0"
        return "\(connID)|\(bluetoothManager.deviceState)|\(received)"
    }

    private func syncLockedFromDeviceIfApplicable() {
        guard isShowingLiveDeviceState else { return }
        let armed = (bluetoothManager.deviceState & 0x01) != 0
        if isLocked != armed {
            isLocked = armed
        }
        settingsManager.setPersistedArmed(armed, for: deviceID)
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
                
                // Right: Battery + MLC state
                if isDeviceConnected {
                    VStack(alignment: .trailing, spacing: 4) {
                        if bluetoothManager.batteryLevel >= 0 {
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
                            .onTapGesture {
                                devTapResetTask?.cancel()
                                devTapCount += 1
                                if devTapCount >= 10 {
                                    devTapCount = 0
                                    settingsManager.devModeUnlocked.toggle()
                                    settingsManager.updateSettings(highPerformance: settingsManager.devModeUnlocked)
                                    if isDeviceConnected { bluetoothManager.sendSettings() }
                                    devModeToast = settingsManager.devModeUnlocked ? "Dev mode on" : "Dev mode off"
                                }
                                devTapResetTask = Task {
                                    try? await Task.sleep(for: .seconds(3))
                                    if !Task.isCancelled { devTapCount = 0 }
                                }
                            }
                        }
                        if mlcIndicatorVisible {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(bluetoothManager.mlcState.color)
                                    .frame(width: 8, height: 8)
                                Text(bluetoothManager.mlcState.displayName)
                                    .font(.caption)
                                    .foregroundColor(bluetoothManager.mlcState.color)
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: mlcIndicatorVisible)
                    .frame(height: 36)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 5)
            .padding(.bottom, 10)
            .opacity((controlsRevealed && !inSettingsMode) ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: controlsRevealed)
            .animation(.easeInOut(duration: 0.3), value: inSettingsMode)

            // MARK: 3D Model Section with Debug Info
            ZStack(alignment: .leading) {
                if isDeviceInRange {
                    // Device is in range (connected or just advertising) — show 3D model
                    if showModel {
                        Motion3DView(
                            bluetoothManager: bluetoothManager,
                            onSettingsTap: isDeviceConnected ? { toggleSettingsMode() } : nil,
                            idleWobble: isDeviceConnected,
                            wobbleIntensity: 0.3,
                            inSettingsMode: inSettingsMode
                        )
                        .frame(maxWidth: .infinity)
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

                            Divider()

                            Text("ACCEL (g)")
                                .font(.system(size: 9))
                                .fontWeight(.bold)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "X", value: String(format: "%.3f", bluetoothManager.debugAccelX))
                                AccelGraph(history: bluetoothManager.accelXHistory, color: .red)
                                    .frame(height: 35)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "Y", value: String(format: "%.3f", bluetoothManager.debugAccelY))
                                AccelGraph(history: bluetoothManager.accelYHistory, color: .green)
                                    .frame(height: 35)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "Z", value: String(format: "%.3f", bluetoothManager.debugAccelZ))
                                AccelGraph(history: bluetoothManager.accelZHistory, color: .blue)
                                    .frame(height: 35)
                            }

                            if settingsManager.dataLoggingMode {
                                Divider()
                                RecordButton(recorder: recorder) { url in
                                    csvShareURL = url
                                    showShareSheet = true
                                }
                            }

                            Divider()

                            Button {
                                showBatteryDiag = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "battery.100.bolt")
                                    Text("Gauge Health")
                                }
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)

                            Button {
                                performDiagnostic()
                            } label: {
                                HStack(spacing: 4) {
                                    if isFetchingDiagnostic {
                                        ProgressView().scaleEffect(0.5)
                                    } else {
                                        Image(systemName: "stethoscope")
                                    }
                                    Text("Diagnostics")
                                }
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.yellow)
                            }
                            .buttonStyle(.plain)
                            .disabled(isFetchingDiagnostic)
                        }
                        .padding(8)
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(8)
                        .shadow(radius: 3)
                        .frame(width: 110)
                        .padding(.leading, 12)
                        .padding(.bottom, 50)

                        Spacer()
                    }
                    .opacity((controlsRevealed && !inSettingsMode) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: controlsRevealed)
                    .animation(.easeInOut(duration: 0.3), value: inSettingsMode)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isDeviceInRange)
            .animation(.easeInOut(duration: 1.0), value: showModel)
            .animation(.easeInOut(duration: 0.3), value: isDeviceConnected)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        guard !inSettingsMode else { return }
                        onOverviewRequest?()
                    }
            )

            // MARK: Bottom Control Section
            VStack(spacing: 12) {
                // Lock button
                LockButton(
                    isLocked: $isLocked,
                    holdProgress: holdProgress,
                    isDisabled: !isDeviceConnected,
                    isStabilizing: bluetoothManager.mlcState == .stabilizing
                )
                .padding(.horizontal, 20)
                .simultaneousGesture(
                    isDeviceConnected ?
                    LongPressGesture(minimumDuration: 0.001)
                        .onChanged { _ in
                            if !isHolding {
                                startHolding()
                            }
                        }
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onEnded { _ in
                            stopHolding()
                        }
                    : nil
                )
                
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
            .opacity((controlsRevealed && !inSettingsMode) ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: controlsRevealed)
            .animation(.easeInOut(duration: 0.3), value: inSettingsMode)
        }
        .statusBar(hidden: true)
        .overlay(alignment: .topLeading) { settingsModeOverlay }
        .sheet(isPresented: $showMotionLogs) {
            NavigationStack {
                MotionLogsView(bluetoothManager: bluetoothManager, deviceID: deviceID)
            }
        }
        .sheet(isPresented: $showBatteryDiag) {
            NavigationStack {
                BatteryDiagnosticView(bluetoothManager: bluetoothManager)
            }
        }
        .onAppear {
            isLocked = settingsManager.persistedArmed(for: deviceID)
            if isShowingLiveDeviceState {
                isLocked = (bluetoothManager.deviceState & 0x01) != 0
            }

            Log.info(.view, "DevicePage appeared [\(deviceID.uuidString.prefix(8))] · connected=\(isDeviceConnected) inRange=\(isDeviceInRange)")

            // Always try to show model if in range
            updateModelVisibility()

            if isDeviceConnected {
                startGraphUpdates()
            }

            // Entrance animation after pairing transition
            if animateEntrance {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        controlsRevealed = true
                    }
                }
            }
        }
        .onDisappear {
            stopGraphUpdates()
            devTapResetTask?.cancel()
            devTapResetTask = nil
        }
        .onChange(of: lockSyncSignal) { _, _ in
            syncLockedFromDeviceIfApplicable()
        }
        .onChange(of: isDeviceConnected) { _, connected in
            if connected {
                // Connection succeeded — clear the connecting flag
                isConnectingThisDevice = false
                Log.info(.view, "Device connected · fading in model")
                withAnimation(.easeInOut(duration: 1.0)) {
                    showModel = true
                }
                startGraphUpdates()
            } else {
                // Device disconnected
                isConnectingThisDevice = false
                Log.info(.view, "Device disconnected")
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
                Log.warn(.view, "Connection attempt ended without success")
                isConnectingThisDevice = false
            }
        }
        .overlay {
            if let toast = devModeToast {
                Text(toast)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(10)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .onChange(of: devModeToast) {
            if devModeToast != nil {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation(.easeInOut(duration: 0.15)) {
                        devModeToast = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = csvShareURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showDiagnostic, onDismiss: { diagnosticSnapshot = nil }) {
            if let snapshot = diagnosticSnapshot {
                DeviceDiagnosticView(snapshot: snapshot)
            }
        }
        .alert(
            "Diagnostics Failed",
            isPresented: Binding(
                get: { diagnosticErrorMessage != nil },
                set: { if !$0 { diagnosticErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { diagnosticErrorMessage = nil }
        } message: {
            Text(diagnosticErrorMessage ?? "")
        }
        .alert("Forget WatchDog?", isPresented: $showForgetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Forget Device", role: .destructive) { forgetDevice() }
        } message: {
            Text("Are you sure you want to forget \(displayName)? You'll need to pair again to reconnect.")
        }
    }

    // MARK: - Diagnostic

    private func performDiagnostic() {
        guard !isFetchingDiagnostic else { return }
        isFetchingDiagnostic = true
        bluetoothManager.requestDiagnostic { result in
            DispatchQueue.main.async {
                isFetchingDiagnostic = false
                switch result {
                case .success(let snapshot):
                    diagnosticSnapshot = snapshot
                    showDiagnostic = true
                case .failure(let error):
                    diagnosticErrorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "No response from device."
                }
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
            Log.info(.view, "Disconnecting from \(currentDevice.name) before connecting to new device")
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
        bluetoothManager.connectByID(deviceID)
    }
    
    private func disconnectDevice() {
        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            Log.info(.view, "User disconnecting from \(device.name)")
            // Do NOT set suppressAutoReconnect here — MainAppView.ensureScanningActive()
            // will clear it anyway, and we need scanning to continue so the device
            // shows as "in range" after disconnecting.
            bluetoothManager.disconnect(from: device)
            
            // Explicitly restart scanning after a short delay to ensure
            // advertisements are picked up again immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.bluetoothManager.suppressAutoReconnect = false
                if self.bluetoothManager.isBluetoothReady && !self.bluetoothManager.isScanning {
                    Log.info(.view, "Restarting scan after disconnect")
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
        holdProgress = 0.09

        lightHaptic.prepare()
        heavyHaptic.prepare()
        lightHaptic.impactOccurred()

        // Drive the fill bar with a repeating timer (~60fps)
        // This avoids relying on withAnimation which can be disrupted by the TabView
        let remainingDuration: Double = isLocked ? 0.6 : 0.91
        let interval: Double = 1.0 / 60.0
        let increment: CGFloat = CGFloat(interval / remainingDuration) * (1.0 - 0.09)

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
        
        let newArmed = !isLocked
        settingsManager.updateSettings(armed: newArmed)
        settingsManager.setPersistedArmed(newArmed, for: deviceID)
        bluetoothManager.sendSettings()
        isLocked = newArmed

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

    // MARK: - Settings Mode

    private func toggleSettingsMode() {
        if inSettingsMode {
            // Exit: fade settings panel out first, then slide model back
            withAnimation(.easeInOut(duration: 0.2)) {
                settingsContentVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                inSettingsMode = false
                onSettingsModeChange?(false)
            }
        } else {
            // Enter: kick off slide + control fade, then fade panel in once
            // the model has cleared the left half of the screen
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            settingsManager.loadDeviceSettings(for: deviceID)
            editableName = displayName
            inSettingsMode = true
            onSettingsModeChange?(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    settingsContentVisible = true
                }
            }
        }
    }

    // MARK: - Settings Bindings

    private var sensitivityBinding: Binding<SensitivityLevel> {
        Binding(
            get: { settingsManager.sensitivity },
            set: { newValue in
                settingsManager.updateSettings(sens: newValue)
                if isDeviceConnected { bluetoothManager.sendSettings() }
            }
        )
    }

    private var alarmTypeBinding: Binding<AlarmType> {
        Binding(
            get: { settingsManager.alarmType },
            set: { newValue in
                settingsManager.updateSettings(alarm: newValue)
                if isDeviceConnected { bluetoothManager.sendSettings() }
            }
        )
    }

    private var silentWhenConnectedBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.disableAlarmWhenConnected },
            set: { newValue in
                settingsManager.updateSettings(disableAlarmConnected: newValue)
                if isDeviceConnected { bluetoothManager.sendSettings() }
            }
        )
    }

    private var lightsEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.lightsEnabled },
            set: { newValue in
                settingsManager.updateSettings(lights: newValue)
                if isDeviceConnected { bluetoothManager.sendSettings() }
            }
        )
    }

    private var loggingEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.loggingEnabled },
            set: { newValue in
                settingsManager.updateSettings(logging: newValue)
                if isDeviceConnected { bluetoothManager.sendSettings() }
            }
        )
    }

    private func forgetDevice() {
        let completion: (Result<Void, Error>) -> Void = { result in
            switch result {
            case .success:
                Log.ok(.bond, "Forget (panel) · UNBOND acked")
            case .failure(let error):
                Log.warn(.bond, "Forget (panel) · UNBOND failed · \(error.localizedDescription)")
            }
        }
        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            bluetoothManager.unpairDevice(completion: completion)
        } else {
            bluetoothManager.unpairDeviceWhileDisconnected(deviceID: deviceID, completion: completion)
        }
        toggleSettingsMode()
    }

    private func commitDeviceName(_ value: String) {
        let limited = String(value.prefix(maxNameLength))
        if limited != editableName { editableName = limited }
        let trimmed = limited.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nameManager.removeCustomName(deviceID: deviceID)
        } else {
            nameManager.setCustomName(deviceID: deviceID, name: trimmed)
        }
    }

    @ViewBuilder
    private var settingsModeOverlay: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top bar — full width. Back's vertical position matches what
                // it had in the previous overlay layout (10pt of vertical
                // padding around .body text), and Settings centers on screen
                // at the same Y as Back.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Button(action: { toggleSettingsMode() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.body)
                        .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Settings")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Content panel — left half, opaque so the model can't bleed
                // through. Inner content is constrained narrower (~2/3 of the
                // panel) so it stays well clear of the model. The settings
                // group is vertically centered to roughly line up with the 3D
                // model in the body underneath.
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("WatchDog", text: $editableName)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray5))
                                .cornerRadius(10)
                                .submitLabel(.done)
                                .onChange(of: editableName) { _, newValue in
                                    commitDeviceName(newValue)
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sensitivity")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            AnimatedSegmentedControl(
                                selection: sensitivityBinding,
                                options: SensitivityLevel.allCases
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Alarm Loudness")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            AnimatedSegmentedControl(
                                selection: alarmTypeBinding,
                                options: AlarmType.allCases
                            )
                        }

                        Toggle(isOn: silentWhenConnectedBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Silent When Connected")
                                    .font(.subheadline)
                                Text("Disable alarm when phone is connected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Toggle("LED Lights", isOn: lightsEnabledBinding)
                            .font(.subheadline)

                        Toggle(isOn: loggingEnabledBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Motion Logging")
                                    .font(.subheadline)
                                Text("Records motion events. Syncs when in range.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(spacing: 8) {
                            Button(action: {
                                guard isDeviceConnected else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                bluetoothManager.sendPing()
                            }) {
                                HStack {
                                    Image(systemName: "speaker.wave.2.fill")
                                    Text("Ping This Device")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(white: 0.2))
                                .cornerRadius(10)
                            }
                            .disabled(!isDeviceConnected)

                            Button(action: { showForgetConfirmation = true }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("Forget This Device")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(white: 0.2))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(width: geo.size.width * 0.67, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .padding(.bottom, 160)
                    .background(Color(.systemBackground))

                    Spacer()
                }
            }
            .overlay(alignment: .bottom) {
                if let label = bluetoothManager.deviceHeader(for: deviceID) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 30)
                }
            }
            .opacity(settingsContentVisible ? 1 : 0)
            .allowsHitTesting(inSettingsMode)
        }
    }
}

#Preview {
    DevicePageView(
        bluetoothManager: BluetoothManager(),
        deviceID: UUID()
    )
}

// MARK: - CubeTestView (debug stand-in for Motion3DView)
// Minimal SCNView with a single rotating cube and basic lighting.
// Used to isolate whether the slide-bump is from the WatchDog USDZ
// asset/shadows/wobble or from SCNView ↔ SwiftUI transform interaction.

struct CubeTestView: UIViewRepresentable {
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        let box = SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0.15)
        box.firstMaterial?.diffuse.contents = UIColor.systemBlue
        box.firstMaterial?.specular.contents = UIColor.white
        let boxNode = SCNNode(geometry: box)
        boxNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 8)))
        scene.rootNode.addChildNode(boxNode)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(camera)

        let omni = SCNNode()
        omni.light = SCNLight()
        omni.light?.type = .omni
        omni.light?.intensity = 800
        omni.position = SCNVector3(3, 5, 5)
        scene.rootNode.addChildNode(omni)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 200
        scene.rootNode.addChildNode(ambient)

        view.scene = scene

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        var onTap: (() -> Void)?
        init(onTap: (() -> Void)?) { self.onTap = onTap }
        @objc func handleTap() { onTap?() }
    }
}
