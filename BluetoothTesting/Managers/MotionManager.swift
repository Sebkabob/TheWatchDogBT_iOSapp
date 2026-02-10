//
//  MotionManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation

/// Simplified MotionManager that only tracks finger-drag rotation.
/// CoreMotion / gyroscope tracking has been removed entirely.
class MotionManager: ObservableObject {
    @Published var rotation = SIMD3<Double>(0, 0, 0)
    
    // No-op stubs kept so existing call sites compile without changes
    func startTracking() { }
    func stopTracking() { }
    func pauseTracking() { }
    func resumeTracking() { }
    
    // Kept for any remaining references
    private(set) var isMotionAvailable = false
}
