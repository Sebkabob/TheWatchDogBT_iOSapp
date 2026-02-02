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
            BondedDevicesListView(bluetoothManager: bluetoothManager)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    MainAppView()
}
