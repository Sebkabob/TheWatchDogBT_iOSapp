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
    @ObservedObject private var bondManager = BondManager.shared
    
    // Current page index in the pager
    @State private var currentPage: Int = 0
    
    // Flag to prevent duplicate setup
    @State private var hasInitialized = false
    
    // Pages layout:
    // Index 0: Add Device page
    // Index 1..N: Device pages (sorted by dateAdded, oldest first)
    // Index N+1: About page
    
    private var sortedDevices: [BondedDevice] {
        bondManager.bondedDevices.sorted { $0.dateAdded < $1.dateAdded }
    }
    
    /// Total number of pages: Add + devices + About
    private var totalPages: Int {
        return 1 + sortedDevices.count + 1
    }
    
    /// Index of a device in the pager (1-based offset from Add page)
    private func pageIndex(for deviceID: UUID) -> Int? {
        guard let deviceIndex = sortedDevices.firstIndex(where: { $0.id == deviceID }) else {
            return nil
        }
        return 1 + deviceIndex
    }
    
    /// Device ID for a given page index, or nil if it's the Add/About page
    private func deviceID(for page: Int) -> UUID? {
        let deviceIndex = page - 1
        guard deviceIndex >= 0 && deviceIndex < sortedDevices.count else {
            return nil
        }
        return sortedDevices[deviceIndex].id
    }
    
    var body: some View {
        TabView(selection: $currentPage) {
            // MARK: - Add Device Page (index 0)
            AddDevicePage(bluetoothManager: bluetoothManager)
                .tag(0)
            
            // MARK: - Device Pages (index 1..N)
            ForEach(Array(sortedDevices.enumerated()), id: \.element.id) { index, device in
                DevicePageView(
                    bluetoothManager: bluetoothManager,
                    deviceID: device.id
                )
                .tag(1 + index)
            }
            
            // MARK: - About Page (last index)
            AboutPage()
                .tag(1 + sortedDevices.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            
            // Start aggressive background scanning immediately.
            // This must stay active at all times so device pages can see
            // which devices are in range via BLE advertisements.
            bluetoothManager.startBackgroundScanning()
            
            // Navigate to last interacted device, or Add page if no devices
            if sortedDevices.isEmpty {
                currentPage = 0
            } else if let lastDeviceID = navState.lastDeviceID,
                      let page = pageIndex(for: lastDeviceID) {
                currentPage = page
            } else if let firstDevice = sortedDevices.first,
                      let page = pageIndex(for: firstDevice.id) {
                // Default to first device if no last interacted
                currentPage = page
            }
        }
        .onChange(of: currentPage) { newPage in
            // Save the current device as last interacted
            if let devID = deviceID(for: newPage) {
                NavigationStateManager.shared.saveDeviceControl(deviceID: devID)
            } else {
                NavigationStateManager.shared.saveDeviceList()
            }
            
            // Ensure scanning is always active when navigating between pages.
            // After a disconnect, suppressAutoReconnect may be true and scanning
            // may have stopped — restart it so other device pages see advertisements.
            ensureScanningActive()
        }
        // When Bluetooth becomes ready, make sure we're scanning
        .onChange(of: bluetoothManager.isBluetoothReady) { ready in
            if ready {
                ensureScanningActive()
            }
        }
        // When a new device is bonded, the sortedDevices array changes
        .onChange(of: bondManager.bondedDevices.count) { newCount in
            // If devices were added and we're on the Add page, jump to the newest device
            if currentPage == 0 && !sortedDevices.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    currentPage = sortedDevices.count // last device = count (1-based)
                }
            }
            // Clamp currentPage if devices were removed
            if currentPage >= totalPages {
                currentPage = max(0, totalPages - 1)
            }
        }
    }
    
    /// Ensure BLE scanning is always running. This is critical because:
    /// - Device pages need fresh advertisements to show "in range" status
    /// - After disconnect, suppressAutoReconnect=true can prevent scanning restart
    /// - The pager needs all devices' RSSI to be up to date
    private func ensureScanningActive() {
        // Always clear suppress flag — in the pager model, the user controls
        // connect/disconnect explicitly via buttons, not via auto-reconnect
        bluetoothManager.suppressAutoReconnect = false
        
        if bluetoothManager.isBluetoothReady && !bluetoothManager.isScanning {
            print("🔍 MainAppView: Restarting background scan")
            bluetoothManager.startBackgroundScanning()
        }
    }
}

// MARK: - Add Device Page
struct AddDevicePage: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var showAddDevice = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Button(action: {
                showAddDevice = true
            }) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 50, weight: .light))
                            .foregroundColor(.blue)
                    }
                    
                    Text("Add a WatchDog")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddDevice) {
            AddNewDeviceView(bluetoothManager: bluetoothManager)
        }
    }
}

// MARK: - About Page
struct AboutPage: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            if colorScheme == .light {
                Image("AppLogoDark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .colorInvert()
            } else {
                Image("AppLogoDark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
            }
            
            Text("WatchDog")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Sebastian Forenza 2026")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainAppView()
}
