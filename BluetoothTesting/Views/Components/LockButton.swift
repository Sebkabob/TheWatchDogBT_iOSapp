//
//  LockButton.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//
import SwiftUI
struct LockButton: View {
    @Binding var isLocked: Bool
    let holdProgress: CGFloat
    
    var buttonColor: Color {
        // Button stays at its current state color, doesn't transition during hold
        return isLocked ? Color.red : Color.black
    }
    
    var body: some View {
        ZStack {
            // Background button
            RoundedRectangle(cornerRadius: 20)
                .fill(buttonColor)
                .frame(height: 80)
            
            // Progress overlay
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: geometry.size.width * holdProgress, height: 80)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            
            // Button content
            HStack(spacing: 15) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.title)
                Text(isLocked ? "Unlock" : "Lock")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
        )
        .shadow(radius: 5)
    }
}
