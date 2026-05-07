//
//  TutorialOverlayView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 4/21/26.
//

import SwiftUI

extension Notification.Name {
    static let showTutorial = Notification.Name("showTutorial")
    static let tutorialCompleted = Notification.Name("tutorialCompleted")
    static let wipeAppDataPerformed = Notification.Name("wipeAppDataPerformed")
}

struct TutorialOverlayView: View {
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var animating = false

    private let stepCount = 3

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button(LocalizationManager.shared.t(.skip)) {
                        onComplete()
                    }
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.trailing, 24)
                    .padding(.top, 16)
                }

                Spacer()

                // Animated illustration. Per-step shortcut gestures live on
                // the outer ZStack below so any part of the screen accepts
                // input — users instinctively swipe / tap / hold anywhere.
                Group {
                    switch currentStep {
                    case 0: swipeIllustration
                    case 1: tapIllustration
                    case 2: holdIllustration
                    default: EmptyView()
                    }
                }
                .frame(height: 200)
                .id(currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer().frame(height: 48)

                // Title & subtitle
                VStack(spacing: 12) {
                    Text(titleForStep)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(subtitleForStep)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                }
                .id(currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStep ? Color.white : Color.white.opacity(0.25))
                            .frame(width: index == currentStep ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: currentStep)
                    }
                }
                .padding(.bottom, 28)

                // Next / Get Started button
                Button(action: advance) {
                    Text(currentStep == stepCount - 1 ? "Get Started" : "Next")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        // Per-step shortcut gestures attached at the ZStack so they fire
        // anywhere on screen. Three separate gestures (drag / tap / long
        // press) keep button priority intact — SwiftUI gives child gestures
        // precedence over a parent's, and Skip/Next are tap-only Buttons.
        // Step 2 needs the long-press hook because a plain tap recogniser
        // never fires once a press exceeds the long-press threshold.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard currentStep == 0 else { return }
                    if abs(value.translation.width) > abs(value.translation.height) {
                        advance()
                    }
                }
        )
        .onTapGesture {
            guard currentStep == 1 || currentStep == 2 else { return }
            advance()
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard currentStep == 2 else { return }
            advance()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                animating = true
            }
        }
        .onChange(of: currentStep) { _, _ in
            animating = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    animating = true
                }
            }
        }
    }

    // MARK: - Step Content

    private var titleForStep: String {
        switch currentStep {
        case 0: "Swipe to Navigate"
        case 1: "Tap for Settings"
        case 2: "Hold to Lock"
        default: ""
        }
    }

    private var subtitleForStep: String {
        switch currentStep {
        case 0: "Swipe left and right to move between your devices and screens"
        case 1: "Tap the 3D model to open your WatchDog's settings"
        case 2: "Press and hold the button to arm or disarm your WatchDog"
        default: ""
        }
    }

    // MARK: - Illustrations

    private var swipeIllustration: some View {
        ZStack {
            // Left/right chevrons that fade based on hand position
            HStack(spacing: 120) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))

                Image(systemName: "chevron.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }

            // Sliding hand
            Image(systemName: "hand.point.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .offset(x: animating ? 50 : -50)
                .animation(
                    animating
                        ? .easeInOut(duration: 1.3).repeatForever(autoreverses: true)
                        : .default,
                    value: animating
                )
        }
    }

    private var tapIllustration: some View {
        ZStack {
            // Ripple rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 80, height: 80)
                    .scaleEffect(animating ? 1.6 + CGFloat(i) * 0.4 : 1.0)
                    .opacity(animating ? 0.0 : 0.5)
                    .animation(
                        animating
                            ? .easeOut(duration: 1.5).repeatForever(autoreverses: false).delay(Double(i) * 0.2)
                            : .default,
                        value: animating
                    )
            }

            // Tap hand
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .scaleEffect(animating ? 0.92 : 1.05)
                .animation(
                    animating
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: animating
                )
        }
    }

    private var holdIllustration: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 5)
                .frame(width: 130, height: 130)

            // Filling progress ring
            Circle()
                .trim(from: 0, to: animating ? 1.0 : 0.0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(-90))
                .animation(
                    animating
                        ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
                        : .default,
                    value: animating
                )

            // Lock icon
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .scaleEffect(animating ? 1.0 : 0.9)
                .animation(
                    animating
                        ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
                        : .default,
                    value: animating
                )
        }
    }

    // MARK: - Actions

    private func advance() {
        if currentStep < stepCount - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                currentStep += 1
            }
        } else {
            onComplete()
        }
    }
}

#Preview {
    TutorialOverlayView(onComplete: {})
}
