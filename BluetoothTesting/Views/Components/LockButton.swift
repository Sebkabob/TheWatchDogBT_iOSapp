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
    var isDisabled: Bool = false
    var isStabilizing: Bool = false

    var buttonColor: Color {
        if isStabilizing {
            return Color.blue
        }
        if isDisabled {
            return isLocked ? Color.red.opacity(0.5) : Color.black.opacity(0.5)
        }
        return isLocked ? Color.red : Color.black
    }

    private var buttonText: String {
        if isStabilizing { return "Stabilizing..." }
        return isLocked ? "Hold to Unlock" : "Hold to Lock"
    }

    private var buttonIcon: String {
        if isStabilizing { return "lock.rotation" }
        return isLocked ? "lock.fill" : "lock.open.fill"
    }

    var body: some View {
        ZStack {
            // Background button
            RoundedRectangle(cornerRadius: 20)
                .fill(buttonColor)
                .frame(height: 80)
                .phaseAnimator(isStabilizing ? [0.6, 1.0] : [1.0]) { content, phase in
                    content.opacity(phase)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }

            // Progress overlay (only show when not disabled and not stabilizing)
            if !isDisabled && !isStabilizing {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.4 * min(holdProgress / 0.09, 1.0)))
                        .frame(width: geometry.size.width * holdProgress, height: 80)
                }
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            // Button content
            HStack(spacing: 15) {
                Image(systemName: buttonIcon)
                    .font(.title)
                Text(buttonText)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .foregroundColor(isDisabled ? .white.opacity(0.6) : .white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
        )
        .shadow(radius: isDisabled ? 2 : 5)
    }
}

#Preview {
    @Previewable @State var locked = true
    LockButton(isLocked: $locked, holdProgress: 0.0)
        .padding()
}
