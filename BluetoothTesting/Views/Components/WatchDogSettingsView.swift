//
//  WatchDogSettingsView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct WatchDogSettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var sensitivity: Double = 50
    @State private var alarmVolume: Double = 75
    @State private var enableVibration = true
    @State private var autoLock = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    Section(header: Text("Motion Detection")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sensitivity")
                                .font(.subheadline)
                            HStack {
                                Text("Low")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Slider(value: $sensitivity, in: 0...100)
                                Text("High")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Section(header: Text("Alarm Settings")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Volume")
                                .font(.subheadline)
                            HStack {
                                Image(systemName: "speaker.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Slider(value: $alarmVolume, in: 0...100)
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Toggle("Vibration", isOn: $enableVibration)
                    }
                    
                    Section(header: Text("Behavior")) {
                        Toggle("Auto-Lock on Connect", isOn: $autoLock)
                    }
                }
                
                VStack(spacing: 0) {
                    Divider()
                    
                    Button(action: {
                        confirmSettings()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Confirm Settings")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle("WatchDog Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
    }
    
    private func confirmSettings() {
        // TODO: Package settings and send via Bluetooth
        dismiss()
    }
}
