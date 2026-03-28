//
//  Motion3DView.swift
//  BluetoothTesting
//

import SwiftUI

struct Motion3DView: View {
    @State private var currentRotationX: Double = 0
    @State private var currentRotationY: Double = 0
    @State private var showSettings = false
    @State private var ledAnimator = LEDAnimator()

    let usdzFileName = "WatchDogBTCase_V2"
    var bluetoothManager: BluetoothManager
    var allowSettingsTap: Bool = true
    var targetDeviceID: UUID? = nil

    private var settingsManager: SettingsManager { SettingsManager.shared }

    var body: some View {
        ZStack {
            SceneView3D(
                rotationX: $currentRotationX,
                rotationY: $currentRotationY,
                usdzFileName: usdzFileName,
                ledColor: ledAnimator.outputColor,
                ledIntensity: ledAnimator.outputIntensity,
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
            syncAnimatorState()
            ledAnimator.start()
        }
        .onDisappear {
            ledAnimator.stop()
        }
        // Re-sync whenever any relevant BLE property changes
        .onChange(of: bluetoothManager.deviceState)    { syncAnimatorState() }
        .onChange(of: bluetoothManager.isCharging)     { syncAnimatorState() }
        .onChange(of: bluetoothManager.isCablePlugged) { syncAnimatorState() }
        .onChange(of: bluetoothManager.isBatteryFull)  { syncAnimatorState() }
        .onChange(of: bluetoothManager.isAlarmActive)  { syncAnimatorState() }
        .onChange(of: bluetoothManager.isFindMyActive) { syncAnimatorState() }
        .onChange(of: bluetoothManager.connectedDevice?.id) { syncAnimatorState() }
        .onChange(of: settingsManager.lightsEnabled)   { syncAnimatorState() }
        .onChange(of: settingsManager.alarmType)       { syncAnimatorState() }
        .onChange(of: settingsManager.isArmed)         { syncAnimatorState() }
    }

    /// Push the current BLE + settings snapshot into the animator's input state.
    private func syncAnimatorState() {
        ledAnimator.isConnected    = bluetoothManager.connectedDevice != nil
        ledAnimator.isArmed        = settingsManager.isArmed
        ledAnimator.lightsEnabled  = settingsManager.lightsEnabled
        ledAnimator.alarmType      = settingsManager.alarmType
        ledAnimator.isCharging     = bluetoothManager.isCharging
        ledAnimator.isCablePlugged = bluetoothManager.isCablePlugged
        ledAnimator.isBatteryFull  = bluetoothManager.isBatteryFull
        ledAnimator.isAlarmActive  = bluetoothManager.isAlarmActive
        ledAnimator.isFindMyActive = bluetoothManager.isFindMyActive
    }
}

#Preview {
    Motion3DView(bluetoothManager: BluetoothManager())
}
