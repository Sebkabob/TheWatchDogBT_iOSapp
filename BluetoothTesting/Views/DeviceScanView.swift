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
            
            // Scan button
            Button(action: {
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScanning()
                } else {
                    bluetoothManager.startScanning()
                }
            }) {
                Text(bluetoothManager.isScanning ? "Stop Scanning" : "Scan for Devices")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bluetoothManager.isScanning ? Color.red : Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(!bluetoothManager.isBluetoothReady)
            
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
                    Text("Tap 'Scan for Devices' to search for WatchDogs")
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
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}
