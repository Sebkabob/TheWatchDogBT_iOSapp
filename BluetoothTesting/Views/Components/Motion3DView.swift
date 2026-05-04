//
//  Motion3DView.swift
//  BluetoothTesting
//

import SwiftUI
import SceneKit

struct Motion3DView: View {
    @State private var currentRotationX: Double = 0
    @State private var currentRotationY: Double = 0
    @State private var currentRotationZ: Double = 0
    @State private var ledAnimator = LEDAnimator()
    @State private var liveQuaternion: SCNVector4? = nil
    @State private var smoothedGX: Double = 0
    @State private var smoothedGY: Double = 1
    @State private var smoothedGZ: Double = 0
    @State private var smoothingSeeded: Bool = false

    var usdzFileName: String = "WatchDogBTCase_V2"
    var bluetoothManager: BluetoothManager
    var onSettingsTap: (() -> Void)? = nil
    var idleWobble: Bool = false
    var wobbleIntensity: Double = 1.0
    var inSettingsMode: Bool = false
    var applyPlasticTexture: Bool = true
    var modelYOffset: Float = 0

    private var settingsManager: SettingsManager { SettingsManager.shared }
    private var isLiveOrientation: Bool { settingsManager.liveOrientationEnabled }

    private var sceneView: some View {
        let wobbleEnabled = idleWobble && !isLiveOrientation
        return SceneView3D(
            rotationX: $currentRotationX,
            rotationY: $currentRotationY,
            rotationZ: $currentRotationZ,
            usdzFileName: usdzFileName,
            ledColor: ledAnimator.outputColor,
            ledIntensity: ledAnimator.outputIntensity,
            gesturesEnabled: !isLiveOrientation,
            idleWobble: wobbleEnabled,
            wobbleIntensity: wobbleIntensity,
            liveQuaternion: liveQuaternion,
            onTap: onSettingsTap,
            inSettingsMode: inSettingsMode,
            applyPlasticTexture: applyPlasticTexture,
            modelYOffset: modelYOffset
        )
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            sceneView
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
        .onChange(of: bluetoothManager.mlcState)        { syncAnimatorState() }
        .onChange(of: settingsManager.lightsEnabled)   { syncAnimatorState() }
        .onChange(of: settingsManager.alarmType)       { syncAnimatorState() }
        .onChange(of: settingsManager.isArmed)         { syncAnimatorState() }
        .onChange(of: settingsManager.disableAlarmWhenConnected) { syncAnimatorState() }
        // Drive model orientation from accelerometer
        .onChange(of: bluetoothManager.debugAccelX) { updateLiveOrientation() }
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
        ledAnimator.mlcState       = bluetoothManager.mlcState
        ledAnimator.silenceEnabled = settingsManager.disableAlarmWhenConnected
    }

    private func updateLiveOrientation() {
        guard isLiveOrientation else {
            if liveQuaternion != nil {
                // Reset so next activation seeds fresh
                smoothingSeeded = false
                liveQuaternion = nil
            }
            return
        }

        let ax = Double(bluetoothManager.debugAccelX)
        let ay = Double(bluetoothManager.debugAccelY)
        let az = Double(bluetoothManager.debugAccelZ)

        let rawMag = sqrt(ax * ax + ay * ay + az * az)
        guard rawMag > 0.1 else { return }

        // Normalize raw input
        let nx = ax / rawMag
        let ny = ay / rawMag
        let nz = az / rawMag

        if !smoothingSeeded {
            // Seed filter with current reading so there's no jump from default
            smoothedGX = nx
            smoothedGY = ny
            smoothedGZ = nz
            smoothingSeeded = true
        }

        // Exponential low-pass filter to reduce jitter
        let alpha = 0.3
        smoothedGX = smoothedGX * (1 - alpha) + nx * alpha
        smoothedGY = smoothedGY * (1 - alpha) + ny * alpha
        smoothedGZ = smoothedGZ * (1 - alpha) + nz * alpha

        let sMag = sqrt(smoothedGX * smoothedGX + smoothedGY * smoothedGY + smoothedGZ * smoothedGZ)
        guard sMag > 0.01 else { return }
        let gx = smoothedGX / sMag
        let gy = smoothedGY / sMag
        let gz = smoothedGZ / sMag

        // Map device coords to SceneKit coords:
        //   Device X (up)    → Scene Y
        //   Device Y (right) → Scene X
        //   Device Z (face)  → Scene -Z (face toward camera = model's -Z direction)
        let sceneX = Float(gy)
        let sceneY = Float(gx)
        let sceneZ = Float(-gz)

        // Compute quaternion that rotates reference up (0,1,0) to the observed gravity direction
        let refX: Float = 0, refY: Float = 1, refZ: Float = 0

        let dot = refX * sceneX + refY * sceneY + refZ * sceneZ

        // Cross product: ref × scene
        let crossX = refY * sceneZ - refZ * sceneY  // 1*sceneZ - 0*sceneY
        let crossY = refZ * sceneX - refX * sceneZ  // 0*sceneX - 0*sceneZ
        let crossZ = refX * sceneY - refY * sceneX  // 0*sceneY - 1*sceneX

        let crossMag = sqrt(crossX * crossX + crossY * crossY + crossZ * crossZ)

        let q: SCNVector4
        if crossMag < 0.0001 {
            if dot > 0 {
                q = SCNVector4(0, 0, 0, 1) // identity
            } else {
                q = SCNVector4(1, 0, 0, 0) // 180° around X
            }
        } else {
            let angle = acos(max(-1, min(1, dot)))
            let halfAngle = angle / 2
            let s = sin(halfAngle) / crossMag
            q = SCNVector4(
                crossX * s,
                crossY * s,
                crossZ * s,
                cos(halfAngle)
            )
        }

        liveQuaternion = q
    }
}

#Preview {
    Motion3DView(bluetoothManager: BluetoothManager())
}
