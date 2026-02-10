//
//  MainAppView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct MainAppView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var navState = NavigationStateManager.shared
    
    // Use this flag to push the device control view exactly once on launch
    @State private var hasRestoredNavigation = false
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            BondedDevicesListView(bluetoothManager: bluetoothManager, navigationPath: $navigationPath)
                .navigationDestination(for: UUID.self) { deviceID in
                    DeviceControlView(bluetoothManager: bluetoothManager, deviceID: deviceID)
                }
        }
        .onAppear {
            restoreNavigationIfNeeded()
        }
    }
    
    private func restoreNavigationIfNeeded() {
        guard !hasRestoredNavigation else { return }
        hasRestoredNavigation = true
        
        if navState.lastScreen == .deviceControl,
           let deviceID = navState.lastDeviceID,
           BondManager.shared.isBonded(deviceID: deviceID) {
            print("🔄 Restoring navigation to device: \(deviceID.uuidString.prefix(8))")
            // Small delay to let the NavigationStack settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigationPath.append(deviceID)
            }
        }
    }
}

#Preview {
    MainAppView()
}
