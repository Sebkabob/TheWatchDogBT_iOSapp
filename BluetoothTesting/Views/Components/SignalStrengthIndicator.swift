//
//  SignalStrengthIndicator.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct SignalStrengthIndicator: View {
    let rssi: Int
    
    // Calculate signal strength (0-4 bars based on RSSI)
    var signalStrength: Int {
        switch rssi {
        case -70...0:
            return 4  // Excellent
        case -85 ..< -70:
            return 3  // Good
        case -95 ..< -85:
            return 2  // Fair
        case -105 ..< -95:
            return 1  // Poor
        default:
            return 0  // Very poor
        }
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < signalStrength ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + index * 3))
            }
        }
        .frame(height: 13)
    }
}
