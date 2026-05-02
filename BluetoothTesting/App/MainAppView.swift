//
//  MainAppView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//
//  ── FIX SUMMARY ──────────────────────────────────────────────────────
//  1. Simplified scan watchdog — just calls ensureScanning() which is
//     now idempotent in BluetoothManager.
//  2. Removed competing scan restart logic (ensureScanningActive was
//     duplicating what the watchdog and BT manager already do).
//  3. Scene phase handling simplified — ensureScanning() handles all
//     edge cases internally now.
//  ─────────────────────────────────────────────────────────────────────

import SwiftUI

struct MainAppView: View {
    @State private var bluetoothManager = BluetoothManager()
    @Environment(\.scenePhase) private var scenePhase
    private let navState = NavigationStateManager.shared
    private let bondManager = BondManager.shared

    @State private var currentPage: Int = 0
    @State private var hasInitialized = false
    @State private var scanWatchdogTimer: Timer?

    // Pairing overlay
    @State private var showPairing = false
    @State private var justPairedDeviceID: UUID?

    // Overview mode
    @State private var isOverviewMode = false
    @State private var deviceToRemove: UUID?
    
    private var sortedDevices: [BondedDevice] {
        bondManager.bondedDevices.sorted { $0.dateAdded < $1.dateAdded }
    }
    
    private var totalPages: Int {
        return 1 + sortedDevices.count + 1
    }
    
    private func pageIndex(for deviceID: UUID) -> Int? {
        guard let deviceIndex = sortedDevices.firstIndex(where: { $0.id == deviceID }) else {
            return nil
        }
        return 1 + deviceIndex
    }
    
    private func deviceID(for page: Int) -> UUID? {
        let deviceIndex = page - 1
        guard deviceIndex >= 0 && deviceIndex < sortedDevices.count else {
            return nil
        }
        return sortedDevices[deviceIndex].id
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                AddDevicePage(bluetoothManager: bluetoothManager, onAddTapped: {
                    if let device = bluetoothManager.connectedDevice {
                        bluetoothManager.disconnect(from: device)
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPairing = true
                    }
                })
                    .tag(0)

                ForEach(Array(sortedDevices.enumerated()), id: \.element.id) { index, device in
                    DevicePageView(
                        bluetoothManager: bluetoothManager,
                        deviceID: device.id,
                        onOverviewRequest: { enterOverviewMode() },
                        animateEntrance: device.id == justPairedDeviceID
                    )
                    .tag(1 + index)
                }

                AboutPage()
                    .tag(1 + sortedDevices.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .scaleEffect(isOverviewMode ? 0.85 : 1.0)
            .opacity(isOverviewMode ? 0 : 1)
            .allowsHitTesting(!isOverviewMode)

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

            // Full-screen pairing overlay
            if showPairing {
                AddNewDeviceView(
                    bluetoothManager: bluetoothManager,
                    onPaired: { deviceID in
                        handlePairingComplete(deviceID: deviceID)
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showPairing = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            
            bluetoothManager.suppressAutoReconnect = false
            bluetoothManager.ensureScanning()
            
            if sortedDevices.isEmpty {
                currentPage = 0
            } else if let lastDeviceID = navState.lastDeviceID,
                      let page = pageIndex(for: lastDeviceID) {
                currentPage = page
            } else if let firstDevice = sortedDevices.first,
                      let page = pageIndex(for: firstDevice.id) {
                currentPage = page
            }
            
            startScanWatchdog()
        }
        .onDisappear {
            scanWatchdogTimer?.invalidate()
            scanWatchdogTimer = nil
        }
        .onChange(of: currentPage) { _, newPage in
            if let devID = deviceID(for: newPage) {
                NavigationStateManager.shared.saveDeviceControl(deviceID: devID)
            } else {
                NavigationStateManager.shared.saveDeviceList()
            }
        }
        .onChange(of: bluetoothManager.isBluetoothReady) { _, ready in
            if ready {
                bluetoothManager.ensureScanning()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Log.info(.view, "App became active · ensuring BLE scan")
                bondManager.refreshTimestampsForForegroundReturn()
                bluetoothManager.handleAppBecameActive()
            }
        }
        .onChange(of: bondManager.bondedDevices.count) { _, newCount in
            if currentPage >= totalPages {
                currentPage = max(0, totalPages - 1)
            }
        }
        .alert("Remove WatchDog?", isPresented: Binding(
            get: { deviceToRemove != nil },
            set: { if !$0 { deviceToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { deviceToRemove = nil }
            Button("Remove", role: .destructive) {
                if let id = deviceToRemove {
                    removeDevice(id)
                    deviceToRemove = nil
                }
            }
        } message: {
            Text("Are you sure you want to remove \(deviceToRemoveName)?")
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isOverviewMode = true
        }
    }

    private func dismissOverviewMode() {
        withAnimation(.easeOut(duration: 0.3)) { isOverviewMode = false }
    }

    private func selectDeviceFromOverview(_ deviceID: UUID) {
        if let page = pageIndex(for: deviceID) { currentPage = page }
        withAnimation(.easeOut(duration: 0.3)) { isOverviewMode = false }
    }

    private func removeDevice(_ deviceID: UUID) {
        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            bluetoothManager.disconnect(from: device)
        }
        bondManager.removeBond(deviceID: deviceID)
        if sortedDevices.isEmpty {
            withAnimation(.easeOut(duration: 0.3)) { isOverviewMode = false }
            currentPage = 0
        }
    }

    private func handlePairingComplete(deviceID: UUID) {
        justPairedDeviceID = deviceID

        // Navigate to the device page behind the overlay
        if let page = pageIndex(for: deviceID) {
            currentPage = page
        }

        // Fade out the overlay to reveal the device page
        withAnimation(.easeInOut(duration: 0.5)) {
            showPairing = false
        }

        // Clear the entrance flag after controls have animated in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            justPairedDeviceID = nil
        }
    }

    /// Simple watchdog: every 5 seconds, call ensureScanning().
    /// ensureScanning() is idempotent so this is always safe.
    private func startScanWatchdog() {
        scanWatchdogTimer?.invalidate()
        scanWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            if bluetoothManager.isBluetoothReady {
                bluetoothManager.ensureScanning()
            }
        }
    }
}

// MARK: - Add Device Page
struct AddDevicePage: View {
    var bluetoothManager: BluetoothManager
    var onAddTapped: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Button(action: { onAddTapped() }) {
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
            Text("Version \(AppVersion.displayString)")
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
