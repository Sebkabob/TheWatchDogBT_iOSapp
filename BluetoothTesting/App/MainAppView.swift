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
    @State private var backgroundDisconnectTimer: Timer?

    // Pairing overlay
    @State private var showPairing = false
    @State private var justPairedDeviceID: UUID?

    // Overview mode
    @State private var isOverviewMode = false
    @State private var deviceToRemove: UUID?

    // Per-device settings overlay state — used to lock TabView paging
    @State private var settingsOverlayActive = false
    
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
    
    /// Page binding that refuses changes while settings/hardware mode is active.
    /// `.scrollDisabled` on `.page`-style TabView is unreliable, so we lock the
    /// selection at the binding level — even if a swipe is recognised, the page
    /// cannot actually change.
    private var lockedPageBinding: Binding<Int> {
        Binding(
            get: { currentPage },
            set: { newValue in
                guard !settingsOverlayActive else { return }
                currentPage = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            TabView(selection: lockedPageBinding) {
                // All pages stay mounted permanently. Tearing down adjacent
                // DevicePageViews (each with its own SCNView/Motion3DView) on
                // every settings entry/exit caused the frame drops during the
                // open/close animation — re-loading the USDZ + rebuilding the
                // scene graph synchronously on the main thread is expensive,
                // and it scaled with the number of bonded devices. Swipe is
                // disabled via the underlying UIScrollView's pan gesture
                // (see SwipeDisabler below) plus the locked binding.
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
                        onSettingsModeChange: { active in settingsOverlayActive = active },
                        animateEntrance: device.id == justPairedDeviceID
                    )
                    .tag(1 + index)
                }

                AboutPage(bluetoothManager: bluetoothManager)
                    .tag(1 + sortedDevices.count)
            }
            .background(SwipeDisabler(disabled: settingsOverlayActive))
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(settingsOverlayActive)
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
                // Cancel any pending background-disconnect timer — user
                // returned within the 5s grace window.
                backgroundDisconnectTimer?.invalidate()
                backgroundDisconnectTimer = nil

                Log.info(.view, "App became active · ensuring BLE scan")
                bondManager.refreshTimestampsForForegroundReturn()
                bluetoothManager.handleAppBecameActive()
            } else if newPhase == .background || newPhase == .inactive {
                // Schedule a 5s disconnect if the user has opted in. Cancelled
                // automatically when the app returns to .active.
                guard AppPreferences.shared.disconnectOnBackground else { return }
                backgroundDisconnectTimer?.invalidate()
                backgroundDisconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                    if let device = bluetoothManager.connectedDevice {
                        Log.info(.view, "Background >5s · disconnecting per user preference")
                        bluetoothManager.disconnect(from: device)
                    }
                    backgroundDisconnectTimer = nil
                }
            }
        }
        .onChange(of: bondManager.bondedDevices.count) { _, newCount in
            if currentPage >= totalPages {
                currentPage = max(0, totalPages - 1)
            }
        }
        .alert(LocalizationManager.shared.t(.removeWatchDogTitle), isPresented: Binding(
            get: { deviceToRemove != nil },
            set: { if !$0 { deviceToRemove = nil } }
        )) {
            Button(LocalizationManager.shared.t(.cancel), role: .cancel) { deviceToRemove = nil }
            Button(LocalizationManager.shared.t(.remove), role: .destructive) {
                if let id = deviceToRemove {
                    removeDevice(id)
                    deviceToRemove = nil
                }
            }
        } message: {
            Text(String(format: LocalizationManager.shared.t(.removeWatchDogMessage), deviceToRemoveName))
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
                    Text(LocalizationManager.shared.t(.addAWatchDog))
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
    let bluetoothManager: BluetoothManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showAppSettings = false

    var body: some View {
        ZStack {
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
            .opacity(showAppSettings ? 0 : 1)

            // Top-right gear button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showAppSettings = true
                        }
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(12)
                    }
                }
                Spacer()
            }
            .opacity(showAppSettings ? 0 : 1)

            // App Settings overlay (fade in/out)
            if showAppSettings {
                AppSettingsView(
                    bluetoothManager: bluetoothManager,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showAppSettings = false
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showAppSettings)
    }
}

// MARK: - App Settings (gear icon → settings)
struct AppSettingsView: View {
    let bluetoothManager: BluetoothManager
    let onBack: () -> Void
    private let loc = LocalizationManager.shared
    private let prefs = AppPreferences.shared
    @State private var showWipeConfirm = false
    @State private var showResetSettingsConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(loc.t(.back))
                    }
                    .font(.body)
                    .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(loc.t(.appSettings))
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Settings content
            Form {
                Section {
                    HStack {
                        Text(loc.t(.language))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { loc.current },
                            set: { loc.current = $0 }
                        )) {
                            ForEach(AppLanguage.allCases, id: \.self) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { prefs.disconnectOnBackground },
                        set: { prefs.disconnectOnBackground = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.t(.disconnectOnBackground))
                            Text(loc.t(.disconnectOnBackgroundCaption))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        showResetSettingsConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                            Text(loc.t(.setToDefaultSettings))
                        }
                        .foregroundColor(.blue)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showWipeConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(loc.t(.wipeAppData))
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .alert(loc.t(.setToDefaultSettingsTitle), isPresented: $showResetSettingsConfirm) {
            Button(loc.t(.cancel), role: .cancel) { }
            Button(loc.t(.reset), role: .destructive) {
                SettingsManager.shared.resetAllDeviceSettingsToDefaults()
                if bluetoothManager.connectedDevice != nil {
                    bluetoothManager.sendSettings()
                }
            }
        } message: {
            Text(loc.t(.setToDefaultSettingsMessage))
        }
        .alert(loc.t(.wipeAppDataConfirmTitle), isPresented: $showWipeConfirm) {
            Button(loc.t(.cancel), role: .cancel) { }
            Button(loc.t(.wipe), role: .destructive) { wipeAppData() }
        } message: {
            Text(loc.t(.wipeAppDataConfirmMessage))
        }
    }

    /// Wipes every persisted preference AND every singleton manager's
    /// in-memory cache. Clearing UserDefaults alone left the bonded device
    /// list intact because each manager (BondManager, DeviceNameManager,
    /// etc.) holds its decoded state in memory and would re-persist on the
    /// next save. Active BLE connections are also torn down.
    private func wipeAppData() {
        bluetoothManager.wipeAllDeviceState()

        BondManager.shared.clearAll()
        DeviceNameManager.shared.clearAll()
        DeviceIconManager.shared.clearAll()
        DeviceNotesManager.shared.clearAll()
        MotionLogManager.shared.clearAll()
        SettingsManager.shared.clearAll()

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Swipe Disabler
/// Walks the UIKit hierarchy from this transparent host view to find every
/// UIScrollView (the one inside UIPageViewController for `.page` TabView, plus
/// any others) and flips their `isScrollEnabled`. SwiftUI's `.scrollDisabled`
/// on `.page` TabView is unreliable across iOS versions, so this is the
/// surgical fix. Pages stay mounted — no expensive view tear-down on settings
/// open/close. Apply runs both immediately AND on next runloop tick so it
/// catches the scroll view whether or not it's been laid out yet.
private struct SwipeDisabler: UIViewRepresentable {
    let disabled: Bool

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let target = disabled
        let apply: () -> Void = {
            // Climb up to the topmost ancestor, then recurse the entire
            // subtree. This guarantees we catch the UIScrollView even when it
            // sits in a sibling branch deeper than one level down.
            var top: UIView = uiView
            while let parent = top.superview { top = parent }
            Self.disableScrollViews(in: top, disabled: target)
        }
        apply()
        DispatchQueue.main.async(execute: apply)
    }

    private static func disableScrollViews(in view: UIView, disabled: Bool) {
        if let sv = view as? UIScrollView {
            sv.isScrollEnabled = !disabled
        }
        for sub in view.subviews {
            disableScrollViews(in: sub, disabled: disabled)
        }
    }
}

#Preview {
    MainAppView()
}
