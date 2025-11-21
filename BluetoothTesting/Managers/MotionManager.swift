//
//  MotionManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation
import CoreMotion
import QuartzCore

class MotionManager: ObservableObject {
    @Published var rotation = SIMD3<Double>(0, 0, 0)
    
    // Debug values to display
    @Published var debugPitch: Double = 0
    @Published var debugRoll: Double = 0
    @Published var debugYaw: Double = 0
    
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private var referenceAttitude: CMAttitude?
    
    // Spring physics parameters
    private var currentRotation = SIMD3<Double>(0, 0, 0)
    
    // Physics tuning parameters - separate spring strengths for each axis
    private let followStrength: Double = 0.18
    private let springStrengthPitch: Double = 0.15
    private let springStrengthRoll: Double = 0.15
    private let damping: Double = 0.88
    private let maxTilt: Double = 0.52
    
    private var displayLink: CADisplayLink?
    private var isPaused = false
    
    func startTracking() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let motion = motion, error == nil else { return }
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if self.referenceAttitude == nil {
                    self.referenceAttitude = motion.attitude.copy() as? CMAttitude
                    return
                }
                
                if let reference = self.referenceAttitude {
                    let attitude = motion.attitude
                    attitude.multiply(byInverseOf: reference)
                    
                    let phonePitch = attitude.pitch
                    let phoneRoll = attitude.roll
                    let phoneYaw = attitude.yaw
                    
                    self.debugPitch = phonePitch
                    self.debugRoll = phoneRoll
                    self.debugYaw = phoneYaw
                    
                    self.updateModelRotation(targetPitch: phonePitch, targetRoll: phoneRoll)
                }
            }
        }
        
        displayLink = CADisplayLink(target: self, selector: #selector(updatePhysics))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private var targetRotation = SIMD3<Double>(0, 0, 0)
    
    private func updateModelRotation(targetPitch: Double, targetRoll: Double) {
        targetRotation.x = clamp(targetPitch, to: maxTilt)
        targetRotation.y = 0
        targetRotation.z = clamp(targetRoll, to: maxTilt)
    }
    
    @objc private func updatePhysics() {
        if isPaused { return }
        
        let followForce = (targetRotation - currentRotation) * followStrength
        
        let springForcePitch = currentRotation.x * -springStrengthPitch
        let springForceRoll = currentRotation.z * -springStrengthRoll
        
        currentRotation.x += followForce.x + springForcePitch
        currentRotation.y = 0
        currentRotation.z += followForce.z + springForceRoll
        
        currentRotation *= damping
        
        rotation = currentRotation
    }
    
    func stopTracking() {
        motionManager.stopDeviceMotionUpdates()
        displayLink?.invalidate()
        displayLink = nil
        referenceAttitude = nil
        currentRotation = SIMD3<Double>(0, 0, 0)
        targetRotation = SIMD3<Double>(0, 0, 0)
    }
    
    func pauseTracking() {
        isPaused = true
    }
    
    func resumeTracking() {
        isPaused = false
    }
    
    private func clamp(_ value: Double, to limit: Double) -> Double {
        return max(-limit, min(limit, value))
    }
}
