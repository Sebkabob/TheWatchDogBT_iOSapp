//
//  WatchDogSettingsView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

struct WatchDogSettingsView: View {
    @Environment(\.dismiss) var dismiss
    private let settingsManager = SettingsManager.shared
    private let bondManager = BondManager.shared
    private let nameManager = DeviceNameManager.shared
    private let iconManager = DeviceIconManager.shared
    var bluetoothManager: BluetoothManager
    
    /// Device ID — used when settings opened from 3D model tap.
    /// Falls back to connected device if nil.
    var targetDeviceID: UUID? = nil
    
    // Resolved device ID: passed-in target or connected device
    private var resolvedDeviceID: UUID? {
        targetDeviceID ?? bluetoothManager.connectedDevice?.id
    }
    
    private var isConnected: Bool {
        guard let devID = resolvedDeviceID else { return false }
        return bluetoothManager.connectedDevice?.id == devID
    }
    
    // Local state for editing
    @State private var watchDogName: String = ""
    @State private var selectedIcon: DeviceIcon = .lockShield
    @State private var sensitivity: SensitivityLevel = .medium
    @State private var alarmType: AlarmType = .normal
    @State private var lightsEnabled: Bool = true
    @State private var loggingEnabled: Bool = false
    @State private var disableAlarmWhenConnected: Bool = false
    @State private var debugModeEnabled: Bool = false
    
    // Forget device confirmation
    @State private var showForgetConfirmation = false
    
    // Character limit for name
    private let maxNameLength = 16
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Settings content
                Form {
                    // WatchDog Name Section
                    Section(header: Text("Device Name")) {
                        TextField("WatchDog Name", text: $watchDogName)
                            .onChange(of: watchDogName) { _, newValue in
                                if newValue.count > maxNameLength {
                                    watchDogName = String(newValue.prefix(maxNameLength))
                                }
                            }
                        
                        Text("\(watchDogName.count)/\(maxNameLength) characters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Icon Picker Section - Horizontal Scrolling
                    Section(header: Text("Device Icon")) {
                        HorizontalIconPicker(selectedIcon: $selectedIcon)
                    }
                    
                    // Sensitivity Section
                    Section(header: Text("Motion Detection")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sensitivity")
                                .font(.subheadline)
                            
                            AnimatedSegmentedControl(
                                selection: $sensitivity,
                                options: SensitivityLevel.allCases
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Alarm Type Section
                    Section(header: Text("Alarm Settings")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Alarm Type")
                                .font(.subheadline)
                            
                            AnimatedSegmentedControl(
                                selection: $alarmType,
                                options: AlarmType.allCases
                            )
                        }
                        .padding(.vertical, 4)
                        
                        // Disable Alarm When Connected Toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Silent When Connected")
                                    .font(.body)
                                Text("Disable alarm when phone is connected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $disableAlarmWhenConnected)
                                .labelsHidden()
                        }
                    }
                    
                    // Lights Section
                    Section(header: Text("LED Indicator")) {
                        HStack {
                            Text("Lights")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: $lightsEnabled)
                                .labelsHidden()
                        }
                    }
                    
                    // Logging Section
                    Section(header: Text("Data Logging")) {
                        HStack {
                            Text("Logging")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: $loggingEnabled)
                                .labelsHidden()
                        }
                        
                        if loggingEnabled {
                            Text("Records motion events locally. Event history syncs automatically when in range.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Debug Mode Section
                    Section(header: Text("Advanced")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Debug Mode")
                                    .font(.body)
                                Text("Show technical diagnostics")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $debugModeEnabled)
                                .labelsHidden()
                        }
                    }
                    
                    // Forget Device Section
                    Section {
                        Button(action: {
                            showForgetConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Forget This Device")
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } footer: {
                        Text("Removes this WatchDog from your bonded devices. You'll need to pair again to reconnect.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Confirm button at bottom
                VStack(spacing: 0) {
                    Divider()
                    
                    Button(action: {
                        applySettings()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Apply Settings")
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
            .onAppear {
                loadCurrentSettings()
            }
            .alert("Forget WatchDog?", isPresented: $showForgetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Forget Device", role: .destructive) {
                    forgetDevice()
                }
            } message: {
                Text("Are you sure you want to forget \(watchDogName)? You'll need to pair again to reconnect.")
            }
        }
    }
    
    private func loadCurrentSettings() {
        guard let deviceID = resolvedDeviceID else { return }
        
        // Load custom name or fall back to advertising name
        if let bond = bondManager.getBond(deviceID: deviceID) {
            watchDogName = nameManager.getDisplayName(deviceID: deviceID, advertisingName: bond.name)
        } else if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            watchDogName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
        }
        
        // Load custom icon or use default
        selectedIcon = iconManager.getDisplayIcon(deviceID: deviceID)
        
        // Load other settings from SettingsManager
        sensitivity = settingsManager.sensitivity
        alarmType = settingsManager.alarmType
        lightsEnabled = settingsManager.lightsEnabled
        loggingEnabled = settingsManager.loggingEnabled
        disableAlarmWhenConnected = settingsManager.disableAlarmWhenConnected
        debugModeEnabled = settingsManager.debugModeEnabled
    }
    
    private func applySettings() {
        guard let deviceID = resolvedDeviceID else { return }
        
        // Save custom name (or remove if blank)
        let trimmedName = watchDogName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            nameManager.removeCustomName(deviceID: deviceID)
            if let bond = bondManager.getBond(deviceID: deviceID) {
                watchDogName = bond.name
            }
        } else {
            nameManager.setCustomName(deviceID: deviceID, name: trimmedName)
        }
        
        // Save custom icon
        iconManager.setCustomIcon(deviceID: deviceID, icon: selectedIcon)
        
        // Update settings manager
        settingsManager.updateSettings(
            alarm: alarmType,
            sens: sensitivity,
            lights: lightsEnabled,
            logging: loggingEnabled,
            disableAlarmConnected: disableAlarmWhenConnected,
            debugMode: debugModeEnabled
        )
        
        // Send settings byte to WatchDog only if connected to this device
        if isConnected {
            bluetoothManager.sendSettings()
        }
        
        print("📤 Settings applied:")
        print("  Custom Name: \(nameManager.hasCustomName(deviceID: deviceID) ? trimmedName : "(using advertising name)")")
        print("  Custom Icon: \(selectedIcon.displayName)")
        print("  Sensitivity: \(sensitivity.rawValue)")
        print("  Alarm Type: \(alarmType.rawValue)")
        print("  Lights: \(lightsEnabled ? "On" : "Off")")
        print("  Logging: \(loggingEnabled ? "On" : "Off")")
        print("  Disable Alarm When Connected: \(disableAlarmWhenConnected ? "Yes" : "No")")
        print("  Debug Mode: \(debugModeEnabled ? "On" : "Off")")
        
        dismiss()
    }
    
    private func forgetDevice() {
        guard let deviceID = resolvedDeviceID else { return }
        
        print("🗑️ Forgetting device: \(watchDogName)")
        
        // Disconnect if connected
        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            bluetoothManager.disconnect(from: device)
        }
        
        // Remove bond
        bondManager.removeBond(deviceID: deviceID)
        
        dismiss()
    }
}

// MARK: - Horizontal Icon Picker
struct HorizontalIconPicker: View {
    @Binding var selectedIcon: DeviceIcon
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DeviceIcon.allCases, id: \.self) { icon in
                    CompactIconButton(
                        icon: icon,
                        isSelected: selectedIcon == icon,
                        onTap: {
                            selectedIcon = icon
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}

struct CompactIconButton: View {
    let icon: DeviceIcon
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: icon.rawValue)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 28, height: 28)
                
                Text(icon.displayName)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 60)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Animated Segmented Control
struct AnimatedSegmentedControl<T: RawRepresentable & Hashable & CaseIterable>: View where T.RawValue == String {
    @Binding var selection: T
    let options: [T]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .frame(width: geometry.size.width / CGFloat(options.count))
                    .offset(x: CGFloat(selectedIndex) * (geometry.size.width / CGFloat(options.count)))
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selection)
                
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        Button(action: {
                            selection = option
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }) {
                            Text(option.rawValue)
                                .font(.subheadline)
                                .fontWeight(selection == option ? .semibold : .regular)
                                .foregroundColor(selection == option ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .frame(height: 36)
    }
    
    private var selectedIndex: Int {
        options.firstIndex(of: selection) ?? 0
    }
}

// MARK: - Enums for Settings

enum SensitivityLevel: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

enum AlarmType: String, CaseIterable {
    case none = "None"
    case calm = "Calm"
    case normal = "Normal"
    case loud = "Loud"
}

#Preview {
    WatchDogSettingsView(bluetoothManager: BluetoothManager())
}
