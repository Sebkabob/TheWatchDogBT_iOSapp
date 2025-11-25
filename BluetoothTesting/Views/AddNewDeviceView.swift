//
//  AddNewDeviceView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 11/23/24.
//

import SwiftUI

struct AddNewDeviceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var bondManager = BondManager.shared
    
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var bondedDeviceName = ""
    
    // Filter out already bonded devices
    private var availableDevices: [BluetoothDevice] {
        bluetoothManager.discoveredDevices.filter { device in
            !bondManager.isBonded(deviceID: device.id)
        }.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Status indicator
                HStack {
                    Circle()
                        .fill(bluetoothManager.isScanning ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(bluetoothManager.isScanning ? "Scanning..." : "Not Scanning")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Device list
                if availableDevices.isEmpty && bluetoothManager.isScanning {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Looking for WatchDogs...")
                            .foregroundColor(.secondary)
                            .padding()
                        Text("Make sure your WatchDog is powered on")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if availableDevices.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No new devices found")
                            .font(.headline)
                        Text("All nearby WatchDogs are already bonded")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else {
                    List(availableDevices) { device in
                        NewDeviceRow(device: device) {
                            bondWithDevice(device)
                        }
                    }
                }
                
                if !bluetoothManager.isBluetoothReady {
                    Text("Bluetooth is not available")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Add WatchDog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                bluetoothManager.startScanning()
            }
            .onDisappear {
                bluetoothManager.stopScanning()
            }
            .alert("WatchDog Added!", isPresented: $showSuccessAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("\(bondedDeviceName) has been bonded and is ready to use.")
            }
            .alert("Pairing Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func bondWithDevice(_ device: BluetoothDevice) {
        print("🔗 Attempting to bond with: \(device.name)")
        
        // Connect to device
        bluetoothManager.connect(to: device)
        
        // Monitor connection status
        // In a real implementation, you'd wait for pairing completion
        // For now, we'll add the bond after connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if bluetoothManager.connectedDevice?.id == device.id {
                // Successfully connected - add bond
                bondManager.addBond(deviceID: device.id, name: device.name)
                bondedDeviceName = device.name
                
                // Disconnect after bonding
                bluetoothManager.disconnect(from: device)
                
                showSuccessAlert = true
            } else {
                errorMessage = "Failed to connect to \(device.name). Please try again."
                showErrorAlert = true
            }
        }
    }
}

struct NewDeviceRow: View {
    let device: BluetoothDevice
    let onTap: () -> Void
    
    @State private var isPressed = false
    @State private var isPairing = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    SignalStrengthIndicator(rssi: device.rssi)
                }
                
                Text(String(device.id.uuidString.prefix(8)))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .monospaced()
                
                Text(isPairing ? "Pairing..." : "Tap to pair")
                    .font(.caption)
                    .foregroundColor(isPairing ? .orange : .blue)
            }
            
            Spacer()
            
            if isPairing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(isPressed ? Color.blue.opacity(0.15) : Color(.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && !isPairing {
                        isPressed = true
                        let generator = UIImpactFeedbackGenerator(style: .soft)
                        generator.impactOccurred()
                    }
                }
                .onEnded { _ in
                    if !isPairing {
                        isPressed = false
                        isPairing = true
                        onTap()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .disabled(isPairing)
    }
}

#Preview {
    AddNewDeviceView(bluetoothManager: BluetoothManager())
}
