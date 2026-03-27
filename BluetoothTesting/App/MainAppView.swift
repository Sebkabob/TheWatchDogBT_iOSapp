//
//  MainAppView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct MainAppView: View {
    @State private var bluetoothManager = BluetoothManager()
    private let navState = NavigationStateManager.shared
    private let bondManager = BondManager.shared
    
    // Current page index in the pager
    @State private var currentPage: Int = 0
    
    // Flag to prevent duplicate setup
    @State private var hasInitialized = false
    
    // Periodic scan health check timer
    @State private var scanWatchdogTimer: Timer?

    // Overview mode (long press to zoom out)
    @State private var isOverviewMode = false
    @State private var deviceToRemove: UUID?
    
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
        ZStack {
            // MARK: - Normal TabView Pager
            TabView(selection: $currentPage) {
                // MARK: Add Device Page (index 0)
                AddDevicePage(bluetoothManager: bluetoothManager)
                    .tag(0)

                // MARK: Device Pages (index 1..N)
                ForEach(Array(sortedDevices.enumerated()), id: \.element.id) { index, device in
                    DevicePageView(
                        bluetoothManager: bluetoothManager,
                        deviceID: device.id,
                        onOverviewRequest: { enterOverviewMode() }
                    )
                    .tag(1 + index)
                }

                // MARK: About Page (last index)
                AboutPage()
                    .tag(1 + sortedDevices.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .scaleEffect(isOverviewMode ? 0.85 : 1.0)
            .opacity(isOverviewMode ? 0 : 1)
            .allowsHitTesting(!isOverviewMode)

            // MARK: - Overview Grid
            if isOverviewMode {
                DeviceOverviewGrid(
                    bluetoothManager: bluetoothManager,
                    devices: sortedDevices,
                    onSelectDevice: { selectDeviceFromOverview($0) },
                    onRemoveDevice: { deviceToRemove = $0 },
                    onDismiss: { dismissOverviewMode() }
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isOverviewMode)
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            
            // Start aggressive background scanning immediately.
            // This must stay active at ALL times so device pages can see
            // which devices are in range via BLE advertisements.
            bluetoothManager.suppressAutoReconnect = false
            bluetoothManager.startBackgroundScanning()
            
            // Navigate to last interacted device, or Add page if no devices
            if sortedDevices.isEmpty {
                currentPage = 0
            } else if let lastDeviceID = navState.lastDeviceID,
                      let page = pageIndex(for: lastDeviceID) {
                currentPage = page
            } else if let firstDevice = sortedDevices.first,
                      let page = pageIndex(for: firstDevice.id) {
                currentPage = page
            }
            
            // Start a periodic watchdog that ensures scanning is ALWAYS alive.
            // This catches any edge case where scanning dies (after disconnect,
            // Bluetooth state changes, etc.)
            startScanWatchdog()
        }
        .onDisappear {
            scanWatchdogTimer?.invalidate()
            scanWatchdogTimer = nil
        }
        .onChange(of: currentPage) { _, newPage in
            // Save the current device as last interacted
            if let devID = deviceID(for: newPage) {
                NavigationStateManager.shared.saveDeviceControl(deviceID: devID)
            } else {
                NavigationStateManager.shared.saveDeviceList()
            }
            
            ensureScanningActive()
        }
        // When Bluetooth becomes ready, make sure we're scanning
        .onChange(of: bluetoothManager.isBluetoothReady) { _, ready in
            if ready {
                ensureScanningActive()
            }
        }
        // When a new device is bonded, the sortedDevices array changes
        .onChange(of: bondManager.bondedDevices.count) { _, newCount in
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
        .alert("Remove WatchDog?", isPresented: Binding(
            get: { deviceToRemove != nil },
            set: { if !$0 { deviceToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                deviceToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let id = deviceToRemove {
                    removeDevice(id)
                    deviceToRemove = nil
                }
            }
        } message: {
            let name = deviceToRemoveName
            Text("Are you sure you want to remove \(name)?")
        }
    }
    
    /// Ensure BLE scanning is always running.
    private func ensureScanningActive() {
        // Always clear suppress flag — in the pager model, the user controls
        // connect/disconnect explicitly via buttons, not via auto-reconnect
        bluetoothManager.suppressAutoReconnect = false
        
        guard bluetoothManager.isBluetoothReady else { return }
        
        if !bluetoothManager.isScanning {
            print("🔍 MainAppView: Restarting background scan")
            bluetoothManager.startBackgroundScanning()
        }
    }
    
    // MARK: - Overview Mode

    private var deviceToRemoveName: String {
        guard let id = deviceToRemove,
              let bond = bondManager.getBond(deviceID: id) else { return "this WatchDog" }
        return DeviceNameManager.shared.getDisplayName(deviceID: id, advertisingName: bond.name)
    }

    private func enterOverviewMode() {
        guard !sortedDevices.isEmpty else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isOverviewMode = true
        }
    }

    private func dismissOverviewMode() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isOverviewMode = false
        }
    }

    private func selectDeviceFromOverview(_ deviceID: UUID) {
        if let page = pageIndex(for: deviceID) {
            currentPage = page
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isOverviewMode = false
        }
    }

    private func removeDevice(_ deviceID: UUID) {
        // Disconnect if this device is currently connected
        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            bluetoothManager.disconnect(from: device)
        }
        bondManager.removeBond(deviceID: deviceID)

        // Exit overview if no devices remain
        if sortedDevices.isEmpty {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isOverviewMode = false
            }
            currentPage = 0
        }
    }

    /// Periodic watchdog that checks every 3 seconds if scanning is still alive.
    /// If scanning has died for any reason, it restarts it.
    private func startScanWatchdog() {
        scanWatchdogTimer?.invalidate()
        scanWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            // Only restart if Bluetooth is ready and we're not scanning
            // Don't restart if we're currently connected (we don't need ads while connected,
            // but it's fine to keep scanning — CoreBluetooth handles this)
            if bluetoothManager.isBluetoothReady && !bluetoothManager.isScanning {
                print("🐕 Scan watchdog: scanning was dead, restarting!")
                bluetoothManager.suppressAutoReconnect = false
                bluetoothManager.startBackgroundScanning()
            }
        }
    }
}

// MARK: - Add Device Page
struct AddDevicePage: View {
    var bluetoothManager: BluetoothManager
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
