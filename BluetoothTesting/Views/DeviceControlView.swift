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
    
    // History for graphs (last 3 minutes)
    @State private var currentHistory: [(date: Date, value: Double)] = []
    @State private var voltageHistory: [(date: Date, value: Double)] = []
    @State private var socHistory: [(date: Date, value: Double)] = []
    @State private var graphUpdateTimer: Timer?
    
    // Track min/max SOC for dynamic range
    @State private var minSOC: Double = 100.0
    @State private var maxSOC: Double = 0.0
    
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
                        // Show charging bolt if charging
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
                            
                            // Voltage row with graph below
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "V", value: String(format: "%.3fV", bluetoothManager.debugVoltage))
                                VoltageGraph(history: voltageHistory)
                                    .frame(height: 35)
                            }
                            
                            // Current row with graph below
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "I", value: String(format: "%.0fmA", bluetoothManager.debugCurrentDraw))
                                CurrentGraph(history: currentHistory)
                                    .frame(height: 35)
                            }
                            
                            // SOC row with graph below
                            VStack(alignment: .leading, spacing: 2) {
                                DebugInfoRow(label: "SOC", value: "\(bluetoothManager.batteryLevel)%")
                                SOCGraph(history: socHistory, minSOC: minSOC, maxSOC: maxSOC)
                                    .frame(height: 35)
                            }
                            
                            DebugInfoRow(label: "Time", value: connectionTimeString)
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
    
    private func startGraphUpdates() {
        // Add initial points
        updateCurrentHistory(bluetoothManager.debugCurrentDraw)
        updateVoltageHistory(bluetoothManager.debugVoltage)
        updateSOCHistory(Double(bluetoothManager.batteryLevel))
        
        // Update graphs every 0.5 seconds
        graphUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.updateCurrentHistory(self.bluetoothManager.debugCurrentDraw)
            self.updateVoltageHistory(self.bluetoothManager.debugVoltage)
            self.updateSOCHistory(Double(self.bluetoothManager.batteryLevel))
        }
    }
    
    private func stopGraphUpdates() {
        graphUpdateTimer?.invalidate()
        graphUpdateTimer = nil
        
        // Reset SOC min/max for next session
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
        
        // Update min/max SOC
        if soc < minSOC {
            minSOC = soc
        }
        if soc > maxSOC {
            maxSOC = soc
        }
    }
    
    private func cleanOldHistory(history: inout [(date: Date, value: Double)]) {
        let cutoff = Date().addingTimeInterval(-180) // Keep last 3 minutes (180 seconds)
        history.removeAll { $0.date < cutoff }
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

struct VoltageGraph: View {
    let history: [(date: Date, value: Double)]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Calculate dynamic Y-axis range from data (excluding first 2 seconds)
            let now = Date()
            let validHistory = history.filter { now.timeIntervalSince($0.date) >= 2.0 }
            
            let dataMin = validHistory.map { $0.value }.min() ?? 3.7
            let dataMax = validHistory.map { $0.value }.max() ?? 4.2
            
            // Dynamic Y-axis range: add ±0.1V, capped at 2.5V-4.2V
            let minY = max(2.5, dataMin - 0.1)
            let maxY = min(4.2, dataMax + 0.1)
            let rangeY = maxY - minY
            
            ZStack(alignment: .bottomLeading) {
                // Background
                Rectangle()
                    .fill(Color(.systemGray6))
                
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Divider()
                            .background(Color.gray.opacity(0.3))
                        Spacer()
                    }
                }
                
                // Graph line
                if validHistory.count > 1 {
                    let maxTimeRange: TimeInterval = 180 // 3 minutes max
                    
                    // Calculate actual time range based on oldest valid data point
                    let oldestTime = validHistory.first?.date ?? now
                    let actualTimeRange = min(now.timeIntervalSince(oldestTime), maxTimeRange)
                    
                    Path { path in
                        for (index, point) in validHistory.enumerated() {
                            // Clamp value to min-max range
                            let clampedValue = max(minY, min(maxY, point.value))
                            
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / actualTimeRange) * width)
                            let normalizedValue = rangeY > 0 ? (clampedValue - minY) / rangeY : 0.5
                            let y = height - (CGFloat(normalizedValue) * height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.purple, lineWidth: 1.5)
                }
                
                // Y-axis labels - show dynamic range
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", maxY))
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", (minY + maxY) / 2))
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", minY))
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 2)
            }
            .cornerRadius(4)
        }
    }
}

struct CurrentGraph: View {
    let history: [(date: Date, value: Double)]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Calculate dynamic Y-axis range from data (excluding first 2 seconds)
            let now = Date()
            let validHistory = history.filter { now.timeIntervalSince($0.date) >= 2.0 }
            
            let dataMin = validHistory.map { $0.value }.min() ?? -50
            let dataMax = validHistory.map { $0.value }.max() ?? 50
            
            // Dynamic Y-axis range: add ±10mA, capped at -300mA to +300mA
            let minY = max(-300, dataMin - 10)
            let maxY = min(300, dataMax + 10)
            let rangeY = maxY - minY
            
            ZStack(alignment: .bottomLeading) {
                // Background
                Rectangle()
                    .fill(Color(.systemGray6))
                
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Divider()
                            .background(Color.gray.opacity(0.3))
                        Spacer()
                    }
                }
                
                // Zero line (if 0 is within range)
                if minY <= 0 && maxY >= 0 {
                    let zeroY = height - (CGFloat((0 - minY) / rangeY) * height)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: zeroY))
                        path.addLine(to: CGPoint(x: width, y: zeroY))
                    }
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                }
                
                // Graph line
                if validHistory.count > 1 {
                    let maxTimeRange: TimeInterval = 180 // 3 minutes max
                    
                    // Calculate actual time range based on oldest valid data point
                    let oldestTime = validHistory.first?.date ?? now
                    let actualTimeRange = min(now.timeIntervalSince(oldestTime), maxTimeRange)
                    
                    Path { path in
                        for (index, point) in validHistory.enumerated() {
                            // Clamp value to min-max range
                            let clampedValue = max(minY, min(maxY, point.value))
                            
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / actualTimeRange) * width)
                            let normalizedValue = rangeY > 0 ? (clampedValue - minY) / rangeY : 0.5
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
                
                // Y-axis labels - show dynamic range
                VStack(spacing: 0) {
                    Text(String(format: "%.0f", maxY))
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", (minY + maxY) / 2))
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", minY))
                        .font(.system(size: 6))
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

struct SOCGraph: View {
    let history: [(date: Date, value: Double)]
    let minSOC: Double
    let maxSOC: Double
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Calculate dynamic Y-axis range from data (excluding first 2 seconds)
            let now = Date()
            let validHistory = history.filter { now.timeIntervalSince($0.date) >= 2.0 }
            
            let dataMin = validHistory.map { $0.value }.min() ?? minSOC
            let dataMax = validHistory.map { $0.value }.max() ?? maxSOC
            
            // Dynamic Y-axis range: add ±2%, capped at 0-100
            let minY = max(0, dataMin - 2)
            let maxY = min(100, dataMax + 2)
            let rangeY = maxY - minY
            
            ZStack(alignment: .bottomLeading) {
                // Background
                Rectangle()
                    .fill(Color(.systemGray6))
                
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Divider()
                            .background(Color.gray.opacity(0.3))
                        Spacer()
                    }
                }
                
                // Graph line
                if validHistory.count > 1 {
                    let maxTimeRange: TimeInterval = 180 // 3 minutes max
                    
                    // Calculate actual time range based on oldest valid data point
                    let oldestTime = validHistory.first?.date ?? now
                    let actualTimeRange = min(now.timeIntervalSince(oldestTime), maxTimeRange)
                    
                    Path { path in
                        for (index, point) in validHistory.enumerated() {
                            // Clamp value to min-max range
                            let clampedValue = max(minY, min(maxY, point.value))
                            
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / actualTimeRange) * width)
                            let normalizedValue = rangeY > 0 ? (clampedValue - minY) / rangeY : 0.5
                            let y = height - (CGFloat(normalizedValue) * height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.green, lineWidth: 1.5)
                }
                
                // Y-axis labels - show dynamic range
                VStack(spacing: 0) {
                    Text("\(Int(maxY))")
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int((minY + maxY) / 2))")
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(minY))")
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 2)
            }
            .cornerRadius(4)
        }
    }
}

#Preview {
    DeviceControlView(bluetoothManager: BluetoothManager())
}
