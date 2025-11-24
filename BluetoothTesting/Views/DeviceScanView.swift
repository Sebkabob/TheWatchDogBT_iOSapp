//
//  DeviceScanView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct DeviceScanView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Debug info
            Text("Devices: \(bluetoothManager.discoveredDevices.count) | Scanning: \(bluetoothManager.isScanning ? "Yes" : "No") | BT Ready: \(bluetoothManager.isBluetoothReady ? "Yes" : "No")")
                .font(.caption)
                .foregroundColor(.blue)
                .padding()
            
            // Device list
            if bluetoothManager.discoveredDevices.isEmpty && bluetoothManager.isScanning {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Scanning for WatchDogs...")
                        .foregroundColor(.secondary)
                        .padding()
                }
                Spacer()
            } else if bluetoothManager.discoveredDevices.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No devices found")
                        .font(.headline)
                    Text("Searching for WatchDogs...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            } else {
                List(bluetoothManager.discoveredDevices) { device in
                    DeviceRow(device: device) {
                        bluetoothManager.connect(to: device)
                    }
                }
            }
            
            if !bluetoothManager.isBluetoothReady {
                Text("Bluetooth is not available")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .navigationTitle("The WatchDog")
        .onAppear {
            print("🟢 DeviceScanView appeared")
            print("🟢 Bluetooth ready: \(bluetoothManager.isBluetoothReady)")
            print("🟢 Currently scanning: \(bluetoothManager.isScanning)")
            bluetoothManager.startScanning()
        }
        .onChange(of: bluetoothManager.isBluetoothReady) { oldValue, newValue in
            print("🔵 Bluetooth ready changed: \(oldValue) -> \(newValue)")
            if newValue && !bluetoothManager.isScanning {
                print("🔵 Starting scan because Bluetooth became ready")
                bluetoothManager.startScanning()
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}
