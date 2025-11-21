//
//  Motion3DView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI
import CoreMotion

struct Motion3DView: View {
    @StateObject private var motionManager = MotionManager()
    @State private var dragRotation: SIMD3<Double> = SIMD3<Double>(0, 0, 0)
    @State private var isDragging = false
    @State private var decayTimer: Timer?
    @State private var showSettings = false
    @StateObject private var ledPulseManager = LEDPulseManager()
    
    let usdzFileName = "WatchDogBTCase_Final"
    var isLocked: Bool = false
    var bluetoothManager: BluetoothManager
    
    var body: some View {
        ZStack {
            SceneView3D(
                rotation: motionManager.rotation,
                dragRotation: dragRotation,
                usdzFileName: usdzFileName,
                ledIntensity: isLocked ? ledPulseManager.pulseIntensity : 0.0
            )
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                            isDragging = true
                            decayTimer?.invalidate()
                            decayTimer = nil
                            
                            let dragSensitivity = 0.005
                            dragRotation = SIMD3<Double>(
                                Double(value.translation.height) * dragSensitivity,
                                0,
                                Double(value.translation.width) * dragSensitivity
                            )
                            motionManager.pauseTracking()
                        }
                    }
                    .onEnded { value in
                        if !isDragging && abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                            showSettings = true
                        }
                        
                        isDragging = false
                        motionManager.resumeTracking()
                        startDecay()
                    }
            )
        }
        .sheet(isPresented: $showSettings) {
            WatchDogSettingsView(bluetoothManager: bluetoothManager)
        }
        .onAppear {
            motionManager.startTracking()
            if isLocked {
                ledPulseManager.startPulsing()
            }
        }
        .onDisappear {
            motionManager.stopTracking()
            decayTimer?.invalidate()
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
    
    private func startDecay() {
        decayTimer?.invalidate()
        
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { timer in
            let decayFactor = 0.92
            
            dragRotation.x *= decayFactor
            dragRotation.y *= decayFactor
            dragRotation.z *= decayFactor
            
            if abs(dragRotation.x) < 0.001 && abs(dragRotation.z) < 0.001 {
                dragRotation = SIMD3<Double>(0, 0, 0)
                timer.invalidate()
                decayTimer = nil
            }
        }
    }
}

#Preview {
    Motion3DView(bluetoothManager: BluetoothManager())
}
