//
//  ContentView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct ContentView: View {
    @State private var showSplash = true
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @State private var showTutorial = false

    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
            } else {
                MainAppView()
                    .transition(.opacity)

                if showTutorial {
                    TutorialOverlayView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showTutorial = false
                            hasSeenTutorial = true
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 1.0)) {
                    showSplash = false
                }
                if !hasSeenTutorial {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showTutorial = true
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTutorial)) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                showTutorial = true
            }
        }
    }
}

struct SplashScreenView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background adapts to color scheme
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if colorScheme == .light {
                    // Light mode: Invert the image
                    Image("AppLogoDark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 250)
                        .colorInvert()
                } else {
                    // Dark mode: Keep as is
                    Image("AppLogoDark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 250)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
