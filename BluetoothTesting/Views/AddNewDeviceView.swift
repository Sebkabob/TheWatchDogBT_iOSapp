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

    // SceneView3D rotation
    @State private var rotX: Double = 0
    @State private var rotY: Double = 0
    @State private var rotZ: Double = 0

    // MARK: - Computed

    /// Available (unbonded) devices sorted by signal strength
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

            VStack(spacing: 0) {
                // Top status
                statusText
                    .padding(.top, 100)
                    .animation(.easeInOut(duration: 0.4), value: phase)

                Spacer()

                // Center: spinner or 3D model
                centerContent

                Spacer()

                // Cancel
                if phase != .paired(phase.deviceID ?? UUID()) {
                    Button("Cancel") { onCancel() }
                        .font(.body)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 50)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            bluetoothManager.ensureScanning()
            checkForDevice()
        }
        .onChange(of: bluetoothManager.discoveredDevices.count) { _, _ in
            checkForDevice()
        }
        .onChange(of: bluetoothManager.connectedDevice) { _, connected in
            guard let id = phase.deviceID,
                  case .pairing = phase,
                  let connected,
                  connected.id == id else { return }
            completePairing(device: connected)
        }
        .onChange(of: bluetoothManager.isConnecting) { _, connecting in
            // Connection attempt failed
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
        case .found(let id):
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

    // MARK: - Center Content

    @ViewBuilder
    private var centerContent: some View {
        switch phase {
        case .searching:
            ProgressView()
                .tint(.white.opacity(0.5))
                .scaleEffect(1.5)
                .transition(.opacity)
        case .found(let id), .pairing(let id), .paired(let id):
            VStack(spacing: 20) {
                ZStack {
                    // Blue glow behind model
                    if glowActive {
                        Circle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: 300, height: 300)
                            .blur(radius: 50)
                            .transition(.opacity)
                    }

                    SceneView3D(
                        rotationX: $rotX,
                        rotationY: $rotY,
                        rotationZ: $rotZ,
                        usdzFileName: "WatchDogBTCase_V2",
                        ledColor: glowActive ? .systemBlue : .darkGray,
                        ledIntensity: glowActive ? 1.0 : 0,
                        gesturesEnabled: true,
                        liveQuaternion: nil,
                        onTap: phase == .found(id) ? { tapToPair(id) } : nil
                    )
                    .frame(height: 350)
                }

                Text(displayName(for: id))
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .opacity(modelVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.8), value: modelVisible)
        }
    }

    // MARK: - Actions

    private func checkForDevice() {
        guard case .searching = phase else { return }
        guard let device = availableDevices.first else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .found(device.id)
        }
        // Fade model in after phase changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            modelVisible = true
        }
    }

    private func tapToPair(_ deviceID: UUID) {
        guard case .found = phase else { return }
        guard let device = bleDevice(for: deviceID) else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

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

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .paired(device.id)
        }

        // Brief pause on "Paired!" then transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onPaired(device.id)
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
