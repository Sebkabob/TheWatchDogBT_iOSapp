//
//  Motion3DView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct Motion3DView: View {
    @State private var currentRotationX: Double = 0  // pitch (up/down)
    @State private var currentRotationY: Double = 0  // yaw (left/right)

    @State private var showSettings = false
    @State private var ledPulseManager = LEDPulseManager()

    let usdzFileName = "WatchDogBTCase_V2"
    var isLocked: Bool = false
    var bluetoothManager: BluetoothManager
    var allowSettingsTap: Bool = true
    /// Device ID to pass to settings when opened (used when tapping 3D model)
    var targetDeviceID: UUID? = nil

    var body: some View {
        ZStack {
            SceneView3D(
                rotationX: $currentRotationX,
                rotationY: $currentRotationY,
                usdzFileName: usdzFileName,
                ledIntensity: isLocked ? ledPulseManager.pulseIntensity : 0.0,
                onTap: allowSettingsTap ? { showSettings = true } : nil
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            WatchDogSettingsView(
                bluetoothManager: bluetoothManager,
                targetDeviceID: targetDeviceID
            )
        }
        .onAppear {
            if isLocked {
                ledPulseManager.startPulsing()
            }
        }
        .onDisappear {
            ledPulseManager.stopPulsing()
        }
        .onChange(of: isLocked) {
            if isLocked {
                ledPulseManager.startPulsing()
            } else {
                ledPulseManager.stopPulsing()
            }
        }
    }
}

#Preview {
    Motion3DView(bluetoothManager: BluetoothManager())
}
