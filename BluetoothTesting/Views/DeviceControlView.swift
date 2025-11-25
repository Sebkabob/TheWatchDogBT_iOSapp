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
            isLocked = settingsManager.isArmed
            print("🎬 View appeared - initial state: isLocked=\(isLocked)")
        }
        .onChange(of: settingsManager.isArmed) { newIsArmed in
            if isLocked != newIsArmed {
                isLocked = newIsArmed
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
}

#Preview {
    DeviceControlView(bluetoothManager: BluetoothManager())
}
