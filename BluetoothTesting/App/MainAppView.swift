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
                // Show control view when connected AND have received initial state
                if bluetoothManager.connectedDevice != nil && bluetoothManager.hasReceivedInitialState {
                    DeviceControlView(bluetoothManager: bluetoothManager)
                        .transition(.opacity)
                        .zIndex(1)
                }
                // Show loading overlay if connected but waiting for state
                else if bluetoothManager.connectedDevice != nil && !bluetoothManager.hasReceivedInitialState {
                    BondedDevicesListView(bluetoothManager: bluetoothManager)
                        .transition(.opacity)
                        .zIndex(0)
                        .overlay(
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
                        )
                }
                // Default: show bonded devices list
                else {
                    BondedDevicesListView(bluetoothManager: bluetoothManager)
                        .transition(.opacity)
                        .zIndex(0)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: bluetoothManager.connectedDevice != nil && bluetoothManager.hasReceivedInitialState)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    MainAppView()
}
