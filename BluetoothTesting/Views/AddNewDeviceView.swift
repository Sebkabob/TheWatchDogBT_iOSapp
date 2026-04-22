//
//  AddNewDeviceView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 11/23/24.
//

import SwiftUI
import SceneKit

struct AddNewDeviceView: View {
    var bluetoothManager: BluetoothManager
    var onPaired: (UUID) -> Void
    var onCancel: () -> Void

    private let bondManager = BondManager.shared
    private let nameManager = DeviceNameManager.shared

    // MARK: - State

    enum PairingPhase: Equatable {
        case searching
        case found(UUID)
        case pairing(UUID)
        case paired(UUID)

        var deviceID: UUID? {
            switch self {
            case .searching: return nil
            case .found(let id), .pairing(let id), .paired(let id): return id
            }
        }
    }

    @State private var phase: PairingPhase = .searching
    @State private var modelVisible = false
    @State private var glowActive = false
    @State private var pairingDone = false
    @State private var readyToShow = false
    @State private var pairingStartTime: Date?
    @State private var statusTextVisible = true

    // SceneView3D rotation
    @State private var rotX: Double = 0
    @State private var rotY: Double = 0
    @State private var rotZ: Double = 0

    // MARK: - Computed

    private var availableDevices: [BluetoothDevice] {
        bluetoothManager.discoveredDevices
            .filter { !bondManager.isBonded(deviceID: $0.id) }
            .sorted { $0.rssi > $1.rssi }
    }

    private func displayName(for deviceID: UUID) -> String {
        if nameManager.hasCustomName(deviceID: deviceID) {
            if let device = bluetoothManager.discoveredDevices.first(where: { $0.id == deviceID }) {
                return nameManager.getDisplayName(deviceID: deviceID, advertisingName: device.name)
            }
        }
        return "WatchDog"
    }

    private func bleDevice(for id: UUID) -> BluetoothDevice? {
        bluetoothManager.discoveredDevices.first { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Match DevicePageView layout: header → model → controls
            VStack(spacing: 0) {

                // Top spacer — matches DevicePageView header height when connected
                Color.clear
                    .frame(height: 36)
                    .padding(.horizontal, 20)
                    .padding(.top, 5)
                    .padding(.bottom, 10)

                // Model area — fills remaining space, same as DevicePageView's ZStack
                ZStack {
                    switch phase {
                    case .searching:
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .scaleEffect(1.5)
                            .transition(.opacity)

                    case .found(let id), .pairing(let id), .paired(let id):
                        ZStack {
                            // Faint white glow when discovered, blue glow when pairing
                            if glowActive {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 300, height: 300)
                                    .blur(radius: 50)
                                    .phaseAnimator([0.15, 0.35]) { content, phase in
                                        content.opacity(phase)
                                    } animation: { _ in
                                        .easeInOut(duration: 1.2)
                                    }
                                    .transition(.opacity)
                            } else if modelVisible {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 320, height: 320)
                                    .blur(radius: 60)
                                    .phaseAnimator([0.05, 0.12]) { content, phase in
                                        content.opacity(phase)
                                    } animation: { _ in
                                        .easeInOut(duration: 2.0)
                                    }
                                    .transition(.opacity)
                            }

                            SceneView3D(
                                rotationX: $rotX,
                                rotationY: $rotY,
                                rotationZ: $rotZ,
                                usdzFileName: "WatchDogBTCase_V2",
                                ledColor: glowActive ? .systemBlue : .darkGray,
                                ledIntensity: glowActive ? 1.0 : 0,
                                gesturesEnabled: false,
                                idleWobble: phase == .found(id),
                                liveQuaternion: nil,
                                onTap: phase == .found(id) ? { tapToPair(id) } : nil
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .opacity(modelVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.8), value: modelVisible)
                        .transition(.opacity)
                    }

                    // Status text overlaid on model area
                    VStack {
                        statusText
                            .padding(.top, 30)
                            .animation(.easeInOut(duration: 0.4), value: phase)
                            .opacity(statusTextVisible ? 1 : 0)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom area — matches DevicePageView control section height
                VStack(spacing: 12) {
                    if case .paired = phase {
                        Color.clear
                    } else {
                        Button("Cancel") { onCancel() }
                            .font(.body)
                            .foregroundColor(.white.opacity(0.4))
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(height: 170)
            }
        }
        .onAppear {
            bluetoothManager.ensureScanning()
            // Show "Searching..." for at least 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                readyToShow = true
                checkForDevice()
            }
        }
        .onChange(of: bluetoothManager.discoveredDevices.count) { _, _ in
            if readyToShow {
                checkForDevice()
            }
        }
        .onChange(of: bluetoothManager.connectedDevice) { _, connected in
            guard let id = phase.deviceID,
                  case .pairing = phase,
                  let connected,
                  connected.id == id else { return }
            completePairing(device: connected)
        }
        .onChange(of: bluetoothManager.isConnecting) { _, connecting in
            if !connecting,
               case .pairing(let id) = phase,
               bluetoothManager.connectedDevice?.id != id {
                withAnimation(.easeInOut(duration: 0.4)) {
                    glowActive = false
                    if !availableDevices.isEmpty {
                        phase = .found(id)
                    } else {
                        modelVisible = false
                        phase = .searching
                    }
                }
            }
        }
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        switch phase {
        case .searching:
            Text("Searching for WatchDogs...")
                .font(.title3)
                .foregroundColor(.white.opacity(0.5))
        case .found:
            Text("Tap to pair")
                .font(.title3)
                .foregroundColor(.white.opacity(0.6))
        case .pairing:
            Text("Pairing...")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        case .paired:
            Text("Paired!")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.green)
        }
    }

    // MARK: - Actions

    private func checkForDevice() {
        guard case .searching = phase else { return }
        guard let device = availableDevices.first else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .found(device.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            modelVisible = true
        }
    }

    private func tapToPair(_ deviceID: UUID) {
        guard case .found = phase else { return }
        guard let device = bleDevice(for: deviceID) else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pairingStartTime = Date()

        withAnimation(.easeInOut(duration: 0.5)) {
            phase = .pairing(deviceID)
            glowActive = true
        }

        bluetoothManager.connect(to: device)
    }

    private func completePairing(device: BluetoothDevice) {
        guard !pairingDone else { return }
        pairingDone = true

        bondManager.addBond(deviceID: device.id, name: device.name)

        // Ensure "Pairing..." shows for at least 1 second
        let elapsed = pairingStartTime.map { Date().timeIntervalSince($0) } ?? 1.0
        let remaining = max(0, 1.0 - elapsed)

        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .paired(device.id)
                glowActive = false
            }

            // Show "Paired!" for 1.25s, then fade text out over 0.25s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                withAnimation(.easeOut(duration: 0.25)) {
                    statusTextVisible = false
                }
                // After text fades, transition to device page
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onPaired(device.id)
                }
            }
        }
    }
}

#Preview {
    AddNewDeviceView(
        bluetoothManager: BluetoothManager(),
        onPaired: { _ in },
        onCancel: { }
    )
}
