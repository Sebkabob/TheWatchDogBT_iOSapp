//
//  Motion3DView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct Motion3DView: View {
    // Drag rotation state
    @State private var currentRotationX: Double = 0  // pitch (up/down)
    @State private var currentRotationY: Double = 0  // yaw (left/right)
    @State private var dragStartRotationX: Double = 0
    @State private var dragStartRotationY: Double = 0
    
    // Momentum / inertia
    @State private var velocityX: Double = 0
    @State private var velocityY: Double = 0
    @State private var lastDragTranslation: CGSize = .zero
    @State private var decayTimer: Timer?
    
    // Tap detection
    @State private var dragStartTime: Date = Date()
    @State private var dragTotalDistance: CGFloat = 0
    @State private var showSettings = false
    
    @StateObject private var ledPulseManager = LEDPulseManager()
    
    let usdzFileName = "WatchDogBTCase_V2"
    var isLocked: Bool = false
    var bluetoothManager: BluetoothManager
    var allowSettingsTap: Bool = true
    /// Device ID to pass to settings when opened (used when tapping 3D model)
    var targetDeviceID: UUID? = nil
    
    // Sensitivity and physics
    private let dragSensitivity: Double = 0.008
    private let maxPitch: Double = 1.2       // limit vertical tilt
    private let decayFactor: Double = 0.95   // momentum decay per frame
    private let minVelocity: Double = 0.0005 // stop threshold
    // Tap thresholds
    private let tapMaxDuration: TimeInterval = 0.25
    private let tapMaxDistance: CGFloat = 8
    
    var body: some View {
        ZStack {
            SceneView3D(
                rotation: SIMD3<Double>(currentRotationX, 0, 0),
                dragRotation: SIMD3<Double>(0, currentRotationY, 0),
                usdzFileName: usdzFileName,
                ledIntensity: isLocked ? ledPulseManager.pulseIntensity : 0.0
            )
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragTotalDistance == 0 && lastDragTranslation == .zero {
                            // Drag just started
                            dragStartTime = Date()
                            dragTotalDistance = 0
                            dragStartRotationX = currentRotationX
                            dragStartRotationY = currentRotationY
                            decayTimer?.invalidate()
                            decayTimer = nil
                        }
                        
                        let deltaW = value.translation.width - lastDragTranslation.width
                        let deltaH = value.translation.height - lastDragTranslation.height
                        dragTotalDistance += sqrt(deltaW * deltaW + deltaH * deltaH)
                        
                        // Update rotation
                        currentRotationY = dragStartRotationY + Double(value.translation.width) * dragSensitivity
                        let newPitch = dragStartRotationX + Double(value.translation.height) * dragSensitivity
                        currentRotationX = max(-maxPitch, min(maxPitch, newPitch))
                        
                        // Track velocity for momentum
                        velocityX = Double(deltaH) * dragSensitivity
                        velocityY = Double(deltaW) * dragSensitivity
                        
                        lastDragTranslation = value.translation
                    }
                    .onEnded { value in
                        let dragDuration = Date().timeIntervalSince(dragStartTime)
                        
                        // Detect tap: short duration + small movement
                        if dragDuration < tapMaxDuration && dragTotalDistance < tapMaxDistance {
                            if allowSettingsTap {
                                showSettings = true
                            }
                        } else {
                            // Start momentum decay
                            startMomentumDecay()
                        }
                        
                        // Reset tracking
                        lastDragTranslation = .zero
                        dragTotalDistance = 0
                    }
            )
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
    
    private func startMomentumDecay() {
        decayTimer?.invalidate()
        
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            velocityX *= decayFactor
            velocityY *= decayFactor
            
            currentRotationY += velocityY
            let newPitch = currentRotationX + velocityX
            currentRotationX = max(-maxPitch, min(maxPitch, newPitch))
            
            if abs(velocityX) < minVelocity && abs(velocityY) < minVelocity {
                velocityX = 0
                velocityY = 0
                timer.invalidate()
                decayTimer = nil
            }
        }
    }
}

#Preview {
    Motion3DView(bluetoothManager: BluetoothManager())
}
