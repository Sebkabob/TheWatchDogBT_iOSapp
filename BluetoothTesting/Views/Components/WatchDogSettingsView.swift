//
//  WatchDogSettingsView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI

// MARK: - Preset Definition

enum WatchDogPreset: String, CaseIterable, Hashable {
    case doorGuard
    case drawerWatch
    case vehicleGuard
    case packageWatch
    case maxSecurity
    case custom

    var displayName: String {
        switch self {
        case .doorGuard:    return "Door Guard"
        case .drawerWatch:  return "Drawer Watch"
        case .vehicleGuard: return "Vehicle Guard"
        case .packageWatch: return "Package Watch"
        case .maxSecurity:  return "Max Security"
        case .custom:       return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .doorGuard:    return "door.left.hand.open"
        case .drawerWatch:  return "cabinet.fill"
        case .vehicleGuard: return "bicycle"
        case .packageWatch: return "shippingbox.fill"
        case .maxSecurity:  return "lock.shield.fill"
        case .custom:       return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .doorGuard:    return "Monitors doors for opening and closing"
        case .drawerWatch:  return "Detects drawer and cabinet access"
        case .vehicleGuard: return "Protects bikes, scooters, and vehicles"
        case .packageWatch: return "Guards packages, bags, and luggage"
        case .maxSecurity:  return "All triggers active, maximum sensitivity"
        case .custom:       return "Configure every setting manually"
        }
    }

    var color: Color {
        switch self {
        case .doorGuard:    return .blue
        case .drawerWatch:  return .purple
        case .vehicleGuard: return .orange
        case .packageWatch: return .green
        case .maxSecurity:  return .red
        case .custom:       return .gray
        }
    }

    var sensitivity: SensitivityLevel {
        switch self {
        case .doorGuard:    return .medium
        case .drawerWatch:  return .low
        case .vehicleGuard: return .high
        case .packageWatch: return .medium
        case .maxSecurity:  return .high
        case .custom:       return .medium
        }
    }

    var alarmType: AlarmType {
        switch self {
        case .doorGuard:    return .normal
        case .drawerWatch:  return .calm
        case .vehicleGuard: return .loud
        case .packageWatch: return .normal
        case .maxSecurity:  return .loud
        case .custom:       return .normal
        }
    }

    var triggers: Set<MotionEventType> {
        switch self {
        case .doorGuard:    return [.doorOpening, .doorClosing]
        case .drawerWatch:  return [.doorOpening, .tilted]
        case .vehicleGuard: return [.inMotion, .shaken, .impact, .freefall]
        case .packageWatch: return [.shaken, .impact, .freefall, .tilted]
        case .maxSecurity:  return [.inMotion, .shaken, .impact, .freefall, .tilted, .doorOpening, .doorClosing]
        case .custom:       return []
        }
    }

    var triggerSummary: String {
        triggers.sorted(by: { $0.rawValue < $1.rawValue }).map(\.displayName).joined(separator: " · ")
    }
}

// MARK: - Main Settings View

struct WatchDogSettingsView: View {
    @Environment(\.dismiss) var dismiss
    private let settingsManager = SettingsManager.shared
    private let bondManager = BondManager.shared
    private let nameManager = DeviceNameManager.shared
    private let notesManager = DeviceNotesManager.shared
    var bluetoothManager: BluetoothManager

    var targetDeviceID: UUID? = nil

    private var resolvedDeviceID: UUID? {
        targetDeviceID ?? bluetoothManager.connectedDevice?.id
    }

    private var isConnected: Bool {
        guard let devID = resolvedDeviceID else { return false }
        return bluetoothManager.connectedDevice?.id == devID
    }

    // Local state
    @State private var watchDogName: String = ""
    @State private var sensitivity: SensitivityLevel = .medium
    @State private var alarmType: AlarmType = .normal
    @State private var alarmDuration: Int = 10
    @State private var disableAlarmWhenConnected: Bool = false
    @State private var debugModeEnabled: Bool = false
    @State private var liveOrientationEnabled: Bool = false
    @State private var dataLoggingMode: Bool = false
    @State private var alarmTriggers: Set<MotionEventType> = []

    // Preset state
    @State private var selectedPreset: WatchDogPreset = .maxSecurity
    @State private var dragOffset: CGFloat = 0

    @State private var showForgetConfirmation = false
    @State private var showResetConfirmation = false
    @State private var deviceNotes: String = ""

    private let maxNameLength = 16

    private let configurableMotionTypes: [MotionEventType] = [
        .inMotion, .shaken, .impact, .freefall, .tilted, .doorOpening, .doorClosing
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    // Hero carousel
                    Section {
                        presetCarousel
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    deviceSection

                    if selectedPreset == .custom {
                        customSensitivitySection
                        customTriggersSection
                        customAlarmSection
                    } else {
                        presetSummarySection
                    }

                    generalSection

                    if settingsManager.devModeUnlocked {
                        debugSection
                    }

                    forgetDeviceSection

                    deviceIdentifierSection
                }

                applyButton
            }
            .navigationTitle("WatchDog Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
            .onAppear { loadCurrentSettings() }
            .alert("Forget WatchDog?", isPresented: $showForgetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Forget Device", role: .destructive) { forgetDevice() }
            } message: {
                Text("Are you sure you want to forget \(watchDogName)? You'll need to pair again to reconnect.")
            }
        }
    }

    // MARK: - Preset Carousel

    private var presetCarousel: some View {
        let presets = WatchDogPreset.allCases
        let count = presets.count
        let selectedIdx = presets.firstIndex(of: selectedPreset) ?? 0

        return GeometryReader { geo in
            let cardWidth = geo.size.width * 0.6
            let spacing: CGFloat = 12
            let step = cardWidth + spacing
            let dragProgress = dragOffset / step

            ZStack {
                ForEach(presets, id: \.self) { preset in
                    let index = presets.firstIndex(of: preset)!
                    let baseDist = circularDistance(from: selectedIdx, to: index, count: count)
                    let dist = Double(baseDist) + dragProgress

                    PresetCard(preset: preset, isSelected: selectedPreset == preset)
                        .frame(width: cardWidth)
                        .scaleEffect(max(0.88, 1.0 - abs(dist) * 0.12))
                        .opacity(max(0, 1.0 - abs(dist) * 0.5))
                        .rotation3DEffect(
                            .degrees(dist * -25),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.4
                        )
                        .offset(x: dist * step)
                        .onTapGesture { selectPreset(preset) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation.width }
                    .onEnded { value in
                        let predicted = value.predictedEndTranslation.width
                        let goNext = predicted < -(step / 2)
                        let goPrev = predicted > step / 2

                        if goNext || goPrev {
                            let nextIdx = goNext
                                ? (selectedIdx + 1) % count
                                : (selectedIdx - 1 + count) % count
                            let targetPreset = presets[nextIdx]
                            let targetOffset = goNext ? -step : step

                            // Animate drag to the snap position
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                dragOffset = targetOffset
                            }

                            // Once settled, swap state instantly (no visual change)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                var t = Transaction(animation: nil)
                                t.disablesAnimations = true
                                withTransaction(t) {
                                    selectedPreset = targetPreset
                                    dragOffset = 0
                                }
                                if targetPreset != .custom {
                                    sensitivity = targetPreset.sensitivity
                                    alarmType = targetPreset.alarmType
                                    alarmTriggers = targetPreset.triggers
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .frame(height: 180)
        .padding(.vertical, 4)
    }

    private func circularDistance(from: Int, to: Int, count: Int) -> Int {
        let raw = to - from
        if raw > count / 2 { return raw - count }
        if raw < -(count / 2) { return raw + count }
        return raw
    }

    private func selectPreset(_ preset: WatchDogPreset) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedPreset = preset
        }
        if preset != .custom {
            sensitivity = preset.sensitivity
            alarmType = preset.alarmType
            alarmTriggers = preset.triggers
        }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - Sections

    private var deviceSection: some View {
        Section(header: Text("Device Name")) {
            TextField("WatchDog Name", text: $watchDogName)
                .onChange(of: watchDogName) { _, newValue in
                    if newValue.count > maxNameLength {
                        watchDogName = String(newValue.prefix(maxNameLength))
                    }
                }
        }
    }

    private var presetSummarySection: some View {
        Section(header: Text("Configuration")) {
            LabeledContent("Sensitivity") {
                Text(sensitivity.rawValue)
                    .foregroundColor(.secondary)
            }
            LabeledContent("Alarm") {
                Text(alarmType.rawValue)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Active Triggers")
                    .font(.subheadline)
                Text(selectedPreset.triggerSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private var customSensitivitySection: some View {
        Section(header: Text("Sensitivity")) {
            VStack(alignment: .leading, spacing: 8) {
                AnimatedSegmentedControl(
                    selection: $sensitivity,
                    options: SensitivityLevel.allCases
                )

                Text(sensitivityDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .animation(.default, value: sensitivity)
            }
            .padding(.vertical, 4)
        }
    }

    private var customTriggersSection: some View {
        Section {
            ForEach(configurableMotionTypes, id: \.self) { motionType in
                SettingToggleRow(
                    title: motionType.displayName,
                    icon: motionType.icon,
                    isOn: Binding(
                        get: { alarmTriggers.contains(motionType) },
                        set: { enabled in
                            if enabled {
                                alarmTriggers.insert(motionType)
                            } else {
                                alarmTriggers.remove(motionType)
                            }
                        }
                    )
                )
            }
        } header: {
            Text("Alarm Triggers")
        } footer: {
            Text("Choose which motion types trigger the alarm.")
        }
    }

    private var customAlarmSection: some View {
        Section(header: Text("Alarm")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alarm Type")
                    .font(.subheadline)

                AnimatedSegmentedControl(
                    selection: $alarmType,
                    options: AlarmType.allCases
                )
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Alarm Duration")
                        .font(.subheadline)
                    Spacer()
                    Text("\(alarmDuration)s")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(alarmDuration) },
                        set: { alarmDuration = Int($0.rounded()) }
                    ),
                    in: 0...30,
                    step: 1
                )

                Text("How long the alarm continues sounding once the device comes to rest after a motion event.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var generalSection: some View {
        Section(header: Text("General")) {
            SettingToggleRow(
                title: "Silent When Connected",
                subtitle: "Disable alarm when phone is connected",
                isOn: $disableAlarmWhenConnected
            )
        }
    }

    private var debugSection: some View {
        Section(header: Text("Debug Tools")) {
            SettingToggleRow(
                title: "Live Orientation",
                subtitle: "3D model mirrors real device orientation",
                isOn: $liveOrientationEnabled
            )
            SettingToggleRow(
                title: "Debug Mode",
                subtitle: "Show hidden technical diagnostics",
                isOn: $debugModeEnabled
            )
            SettingToggleRow(
                title: "Data Logging",
                subtitle: "Record accel data to CSV for MLC training",
                isOn: $dataLoggingMode
            )
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    UserDefaults.standard.set(false, forKey: "hasSeenTutorial")
                    NotificationCenter.default.post(name: .showTutorial, object: nil)
                }
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text("Show Tutorial")
                }
            }
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.circle")
                    Text("Reset Device")
                }
            }
            .disabled(!isConnected)
            .confirmationDialog(
                "Reset Device?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    bluetoothManager.sendResetDevice()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will immediately reboot the WatchDog. The BLE connection will drop.")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $deviceNotes)
                    .font(.body)
                    .frame(minHeight: 60)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: deviceNotes) {
                        if let deviceID = resolvedDeviceID {
                            notesManager.setNotes(deviceID: deviceID, text: deviceNotes)
                        }
                    }
            }
        }
    }

    private var forgetDeviceSection: some View {
        Section {
            Button(action: { showForgetConfirmation = true }) {
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

    private var deviceIdentifierSection: some View {
        Section {
            EmptyView()
        } footer: {
            if let label = watchDogIdentifierLabel {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var watchDogIdentifierLabel: String? {
        guard let deviceID = resolvedDeviceID else { return nil }
        return bluetoothManager.deviceHeader(for: deviceID)
    }

    private var applyButton: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: { applySettings() }) {
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

    // MARK: - Helpers

    private var sensitivityDescription: String {
        switch sensitivity {
        case .low:
            return "Identifies motion type before triggering. Reduces false alarms."
        case .medium:
            return "Balances identification and detection speed."
        case .high:
            return "Triggers on any motion immediately. Maximum security."
        }
    }

    private func loadCurrentSettings() {
        guard let deviceID = resolvedDeviceID else { return }

        if let bond = bondManager.getBond(deviceID: deviceID) {
            watchDogName = nameManager.getDisplayName(deviceID: deviceID, advertisingName: bond.name)
        } else if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            watchDogName = nameManager.getDisplayName(deviceID: device.id, advertisingName: device.name)
        }

        deviceNotes = notesManager.getNotes(deviceID: deviceID)

        // Load this device's saved settings
        settingsManager.loadDeviceSettings(for: deviceID)

        sensitivity = settingsManager.sensitivity
        alarmType = settingsManager.alarmType
        alarmDuration = settingsManager.alarmDuration
        disableAlarmWhenConnected = settingsManager.disableAlarmWhenConnected
        debugModeEnabled = settingsManager.debugModeEnabled
        liveOrientationEnabled = settingsManager.liveOrientationEnabled
        dataLoggingMode = settingsManager.dataLoggingMode
        alarmTriggers = settingsManager.alarmTriggers

        if let preset = WatchDogPreset(rawValue: settingsManager.selectedPresetRawValue) {
            selectedPreset = preset
        }
    }

    private func applySettings() {
        guard let deviceID = resolvedDeviceID else { return }

        let trimmedName = watchDogName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            nameManager.removeCustomName(deviceID: deviceID)
            if let bond = bondManager.getBond(deviceID: deviceID) {
                watchDogName = bond.name
            }
        } else {
            nameManager.setCustomName(deviceID: deviceID, name: trimmedName)
        }

        settingsManager.updateSettings(
            alarm: alarmType,
            sens: sensitivity,
            disableAlarmConnected: disableAlarmWhenConnected,
            debugMode: debugModeEnabled,
            highPerformance: settingsManager.devModeUnlocked,
            liveOrientation: liveOrientationEnabled,
            dataLogging: dataLoggingMode,
            triggers: alarmTriggers,
            preset: selectedPreset.rawValue,
            alarmDuration: alarmDuration
        )

        if isConnected {
            bluetoothManager.sendSettings()
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        dismiss()
    }

    private func forgetDevice() {
        guard let deviceID = resolvedDeviceID else { return }

        let completion: (Result<Void, Error>) -> Void = { result in
            switch result {
            case .success:
                Log.ok(.bond, "Forget (settings) · UNBOND acked")
            case .failure(let error):
                Log.warn(.bond, "Forget (settings) · UNBOND failed · \(error.localizedDescription)")
            }
        }

        if let device = bluetoothManager.connectedDevice, device.id == deviceID {
            bluetoothManager.unpairDevice(completion: completion)
        } else {
            bluetoothManager.unpairDeviceWhileDisconnected(deviceID: deviceID, completion: completion)
        }

        dismiss()
    }
}

// MARK: - Preset Card

struct PresetCard: View {
    let preset: WatchDogPreset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: preset.icon)
                .font(.system(size: 34, weight: .medium))

            Text(preset.displayName)
                .font(.headline)

            Text(preset.description)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .opacity(0.85)
        }
        .foregroundColor(.white)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(preset.color.gradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2.5)
        )
        .shadow(color: isSelected ? preset.color.opacity(0.4) : .clear, radius: 8, y: 4)
    }
}

// MARK: - Reusable Setting Toggle Row

struct SettingToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
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
                    ForEach(Array(options.enumerated()), id: \.element) { _, option in
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

// MARK: - Enums

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
