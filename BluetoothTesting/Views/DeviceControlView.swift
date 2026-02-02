//
//  DeviceControlView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct DeviceControlView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var nameManager = DeviceNameManager.shared
    @State private var isLocked = true
    @State private var holdProgress: CGFloat = 0.0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    @State private var showMotionLogs = false
    
    // Current consumption history for graph (last 10 seconds)
    @State private var currentHistory: [(date: Date, value: Double)] = []
    @State private var graphUpdateTimer: Timer?
    
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    
    // Get display name for connected device
    private var displayName: String {
        guard let device = bluetoothManager.connectedDevice else { return "WatchDog" }
        return nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Device State Display at the top - Horizontal Layout
            HStack(alignment: .center, spacing: 0) {
                // Left: Device name
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Center: Lock state
                HStack(spacing: 8) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 12, height: 12)
                    
                    Text(bluetoothManager.deviceStateText)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(stateColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // Right: Battery indicator
                if bluetoothManager.batteryLevel >= 0 {
                    HStack(spacing: 4) {
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
            
            // 3D Model Section with Debug Info
            ZStack(alignment: .leading) {
                // 3D Model - Centered
                Motion3DView(isLocked: isLocked, bluetoothManager: bluetoothManager)
                    .frame(maxWidth: .infinity)
                
                // Debug Info Box - Left side
                if settingsManager.debugModeEnabled {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DEBUG")
                                .font(.system(size: 9))
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            
                            Divider()
                            
                            DebugInfoRow(label: "V", value: String(format: "%.2fV", bluetoothManager.debugVoltage))
                            DebugInfoRow(label: "I", value: String(format: "%.0fmA", bluetoothManager.debugCurrentDraw))
                            DebugInfoRow(label: "SOC", value: "\(bluetoothManager.batteryLevel)%")
                            DebugInfoRow(label: "Time", value: connectionTimeString)
                            
                            // Mini current consumption graph
                            CurrentGraph(history: currentHistory)
                                .frame(height: 45)
                                .padding(.top, 4)
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
            
            // Bottom Control Section - Fixed, not scrollable
            VStack(spacing: 12) {
                // Single Lock/Unlock button
                LockButton(
                    isLocked: $isLocked,
                    holdProgress: holdProgress
                )
                .padding(.horizontal, 20)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isHolding {
                                startHolding()
                            }
                        }
                        .onEnded { _ in
                            stopHolding()
                        }
                )
                
                // Disconnect and Motion Logs buttons side by side
                HStack(spacing: 12) {
                    // Disconnect button (left, red)
                    Button(action: {
                        if let device = bluetoothManager.connectedDevice {
                            bluetoothManager.disconnect(from: device)
                            dismiss()
                        }
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
            print("🎬 View appeared - initial state: isLocked=\(isLocked)")
            startGraphUpdates()
        }
        .onDisappear {
            stopGraphUpdates()
        }
        .onChange(of: settingsManager.isArmed) { newIsArmed in
            if isLocked != newIsArmed {
                isLocked = newIsArmed
            }
        }
        .onChange(of: bluetoothManager.debugCurrentDraw) { newCurrent in
            updateCurrentHistory(newCurrent)
        }
        .onChange(of: bluetoothManager.connectedDevice) { device in
            // Auto-dismiss if disconnected
            if device == nil {
                dismiss()
            }
        }
    }
    
    private var stateColor: Color {
        let isArmed = (bluetoothManager.deviceState & 0x01) != 0
        return isArmed ? .red : .green
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
        let level = bluetoothManager.batteryLevel
        
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
    
    private func startGraphUpdates() {
        graphUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            cleanOldHistory()
        }
    }
    
    private func stopGraphUpdates() {
        graphUpdateTimer?.invalidate()
        graphUpdateTimer = nil
    }
    
    private func updateCurrentHistory(_ current: Double) {
        let now = Date()
        currentHistory.append((date: now, value: current))
        cleanOldHistory()
    }
    
    private func cleanOldHistory() {
        let cutoff = Date().addingTimeInterval(-10) // Keep last 10 seconds
        currentHistory.removeAll { $0.date < cutoff }
    }
}

struct DebugInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 9))
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .monospaced()
        }
    }
}

struct CurrentGraph: View {
    let history: [(date: Date, value: Double)]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Fixed Y-axis range: -300mA to +300mA
            let minY: Double = -300
            let maxY: Double = 300
            let rangeY = maxY - minY
            
            ZStack(alignment: .bottomLeading) {
                // Background
                Rectangle()
                    .fill(Color(.systemGray6))
                
                // Grid lines (3 horizontal lines)
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Divider()
                            .background(Color.gray.opacity(0.3))
                        Spacer()
                    }
                }
                
                // Zero line (middle of graph)
                let zeroY = height - (CGFloat((0 - minY) / rangeY) * height)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: zeroY))
                    path.addLine(to: CGPoint(x: width, y: zeroY))
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                
                // Graph line
                if history.count > 1 {
                    let now = Date()
                    let timeRange: TimeInterval = 10 // 10 seconds
                    
                    Path { path in
                        for (index, point) in history.enumerated() {
                            // Clamp value to ±300mA
                            let clampedValue = max(minY, min(maxY, point.value))
                            
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / timeRange) * width)
                            let normalizedValue = (clampedValue - minY) / rangeY
                            let y = height - (CGFloat(normalizedValue) * height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(lineColor, lineWidth: 1.5)
                }
                
                // Y-axis labels (max, zero, min)
                VStack(spacing: 0) {
                    Text("+300")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("-300")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 2)
            }
            .cornerRadius(4)
        }
    }
    
    // Determine line color based on most recent value
    private var lineColor: Color {
        guard let lastValue = history.last?.value else { return .blue }
        return lastValue < 0 ? .green : .blue  // Negative = charging (green), Positive = discharging (blue)
    }
}

#Preview {
    DeviceControlView(bluetoothManager: BluetoothManager())
}
