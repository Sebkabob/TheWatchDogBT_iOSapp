//
//  MainAppView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct MainAppView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Only show control view when connected AND have received initial state
                if bluetoothManager.connectedDevice != nil && bluetoothManager.hasReceivedInitialState {
                    DeviceControlView(bluetoothManager: bluetoothManager)
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    // Show scan view with loading indicator if connected but waiting for state
                    DeviceScanView(bluetoothManager: bluetoothManager)
                        .transition(.opacity)
                        .zIndex(0)
                        .overlay(
                            Group {
                                if bluetoothManager.connectedDevice != nil && !bluetoothManager.hasReceivedInitialState {
                                    VStack(spacing: 16) {
                                        ProgressView()
                                            .scaleEffect(1.5)
                                        Text("Syncing with WatchDog...")
                                            .font(.headline)
                                        Text("Sniffing for information...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(32)
                                    .background(Color(.systemBackground).opacity(0.95))
                                    .cornerRadius(16)
                                    .shadow(radius: 10)
                                }
                            }
                        )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: bluetoothManager.connectedDevice != nil && bluetoothManager.hasReceivedInitialState)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
