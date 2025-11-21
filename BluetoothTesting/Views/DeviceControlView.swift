//
//  DeviceControlView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct DeviceControlView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var isLocked = true
    @State private var holdProgress: CGFloat = 0.0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    
    // Add haptic generators
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        VStack(spacing: 0) {
            // Device State Display at the top - Horizontal Layout
            HStack(alignment: .center, spacing: 0) {
                // Left: Device name
                if let deviceName = bluetoothManager.connectedDevice?.name {
                    Text(deviceName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
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
            
            // 3D Model Section - Centered and takes up most of the screen
            Spacer()
            Motion3DView(isLocked: isLocked, bluetoothManager: bluetoothManager)
                .frame(maxWidth: .infinity)
            Spacer()
            
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
                
                // Disconnect button
                Button(action: {
                    if let device = bluetoothManager.connectedDevice {
                        bluetoothManager.disconnect(from: device)
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
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            // Initialize state from settings manager
            isLocked = settingsManager.isArmed
            print("🎬 View appeared - initial state: isLocked=\(isLocked), deviceState=\(bluetoothManager.deviceState)")
        }
        .onChange(of: settingsManager.isArmed) { newIsArmed in
            print("🔄 Settings manager armed changed: \(newIsArmed)")
            
            // Only update if different to avoid fighting with optimistic updates
            if isLocked != newIsArmed {
                print("⚠️ Correcting state mismatch: local=\(isLocked), settings=\(newIsArmed)")
                isLocked = newIsArmed
            }
        }
    }
    
    // Helper computed property for state color
    private var stateColor: Color {
        // Extract the armed bit (bit 0) from the settings byte
        let isArmed = (bluetoothManager.deviceState & 0x01) != 0
        
        if isArmed {
            return .red  // Locked = Red
        } else {
            return .green  // Unlocked = Green
        }
        
        // You can add orange for alarming state later if needed
    }
    
    private func startHolding() {
        isHolding = true
        holdProgress = 0.0
        print("🟡 Started holding - current state: isLocked=\(isLocked)")
        
        // Prepare haptics for reduced latency
        lightHaptic.prepare()
        heavyHaptic.prepare()
        
        // Single haptic at start
        lightHaptic.impactOccurred()
        
        // Use smooth animation for progress instead of manual timer updates
        withAnimation(.linear(duration: 1.0)) {
            holdProgress = 1.0
        }
        
        // Single timer just for completion
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
        print("🔴 Stopped holding early")
        
        // Animate progress back to 0
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    private func completeHold() {
        print("✅ Hold complete - current isLocked=\(isLocked)")
        
        // Heavy haptic at completion
        heavyHaptic.impactOccurred(intensity: 1.0)
        
        // Toggle armed state in settings manager
        settingsManager.updateSettings(armed: !isLocked)
        
        // Send updated settings byte (with new armed state)
        bluetoothManager.sendSettings()
        
        // Optimistically update the UI immediately
        isLocked.toggle()
        print("🔄 Optimistically toggled to isLocked=\(isLocked)")
        
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    private func sendHexValue(_ hexString: String) {
        var data = Data()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        bluetoothManager.sendData(data)
    }
    
    // Helper computed property for battery icon with more detail
    private var batteryIcon: String {
        let level = bluetoothManager.batteryLevel
        
        // 100%
        if level == 100 { return "battery.100" }
        
        // 90-99%
        if level >= 90 { return "battery.100" }
        
        // 75-89%
        if level >= 75 { return "battery.75" }
        
        // 60-74%
        if level >= 60 { return "battery.75" }
        
        // 50-59%
        if level >= 50 { return "battery.50" }
        
        // 40-49%
        if level >= 40 { return "battery.50" }
        
        // 25-39%
        if level >= 25 { return "battery.25" }
        
        // 10-24%
        if level >= 10 { return "battery.25" }
        
        // 1-9%
        if level > 0 { return "battery.0" }
        
        // 0% or unknown
        return "battery.0"
    }

    // Helper computed property for battery color
    private var batteryColor: Color {
        let level = bluetoothManager.batteryLevel
        if level >= 20 { return .green }
        if level >= 10 { return .orange }
        return .red
    }
}
