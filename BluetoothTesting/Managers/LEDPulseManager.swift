//
//  LEDPulseManager.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Foundation

class LEDPulseManager: ObservableObject {
    @Published var pulseIntensity: Double = 0.0
    
    private var timer: Timer?
    private var pulseValue: Double = 0.0
    private var pulseDirection: Int = 1  // 1 = increasing, 0 = decreasing
    private let pulseStep: Double = 0.02
    private let updateInterval: TimeInterval = 0.01
    
    func startPulsing() {
        guard timer == nil else { return }
        
        pulseValue = 0.0
        pulseDirection = 1
        
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updatePulse()
        }
    }
    
    func stopPulsing() {
        timer?.invalidate()
        timer = nil
        pulseIntensity = 0.0
        pulseValue = 0.0
        pulseDirection = 1
    }
    
    private func updatePulse() {
        let minPulse: Double = 0.0
        let maxPulse: Double = 0.9
        
        if pulseDirection == 1 {
            pulseValue += pulseStep
            if pulseValue >= maxPulse {
                pulseDirection = 0
            }
        } else {
            pulseValue -= pulseStep
            if pulseValue <= minPulse {
                pulseDirection = 1
            }
        }
        
        let invertedPulse = 1.0 - pulseValue
        pulseIntensity = invertedPulse
    }
}
