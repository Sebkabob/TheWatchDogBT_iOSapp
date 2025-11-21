//
//  ContentView.swift
//  BluetoothTesting
//
//  Created by Sebastian Forenza on 10/30/25.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
            } else {
                MainAppView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Hide splash screen after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 1.0)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash Screen
struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.red.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // App Logo
                Image("AppLogoDark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250, height: 250)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Main App View (Navigation Container)
struct MainAppView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                if bluetoothManager.connectedDevice != nil {
                    DeviceControlView(bluetoothManager: bluetoothManager)
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    DeviceScanView(bluetoothManager: bluetoothManager)
                        .transition(.opacity)
                        .zIndex(0)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: bluetoothManager.connectedDevice != nil)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Device Scan View
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
        .navigationTitle("The WatchDog (Alpha)")
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: - Device Row Component
struct DeviceRow: View {
    let device: BluetoothDevice
    let onTap: () -> Void
    @State private var isPressed = false
    @State private var isConnecting = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Signal strength bars next to name
                    SignalStrengthIndicator(rssi: device.rssi)
                }
                
                // Show device UUID for identification
                Text(String(device.id.uuidString.prefix(8)))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .monospaced()
                
                Text(isConnecting ? "Connecting..." : "Tap to connect")
                    .font(.caption)
                    .foregroundColor(isConnecting ? .orange : .blue)
            }
            
            Spacer()
            
            if isConnecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
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
                    if !isPressed && !isConnecting {
                        isPressed = true
                        // Trigger haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .soft)
                        generator.impactOccurred()
                    }
                }
                .onEnded { _ in
                    if !isConnecting {
                        isPressed = false
                        isConnecting = true
                        onTap()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .disabled(isConnecting)
    }
}

// MARK: - Signal Strength Indicator
struct SignalStrengthIndicator: View {
    let rssi: Int
    
    // Calculate signal strength (0-4 bars based on RSSI)
    var signalStrength: Int {
        switch rssi {
        case -65...0:
            return 4  // Excellent
        case -80 ..< -65:
            return 3  // Good
        case -90 ..< -80:
            return 2  // Fair
        case -95 ..< -90:
            return 1  // Poor
        default:
            return 0  // Very poor
        }
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < signalStrength ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + index * 3))
            }
        }
        .frame(height: 13)
    }
}

// MARK: - Device Control View
struct DeviceControlView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isLocked = true
    @State private var holdProgress: CGFloat = 0.0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Device State Display at the top
            VStack(spacing: 8) {
                // Show device name
                if let deviceName = bluetoothManager.connectedDevice?.name {
                    Text(deviceName)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Text("Device State:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 12, height: 12)
                    
                    Text(bluetoothManager.deviceStateText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(stateColor)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            // 3D Model Section - Centered and takes up most of the screen
            Spacer()
            Motion3DView(isLocked: isLocked)
                .frame(maxWidth: .infinity)
            Spacer()
            
            // Bottom Control Section - Fixed, not scrollable
            VStack(spacing: 12) {
                // Single Lock/Unlock button
                LockButton(
                    isLocked: $isLocked,
                    holdProgress: holdProgress
                )
                .padding(.horizontal, 20)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isHolding {
                                startHolding()
                            }
                        }
                        .onEnded { _ in
                            stopHolding()
                        }
                )
                
                // Disconnect button
                Button(action: {
                    if let device = bluetoothManager.connectedDevice {
                        bluetoothManager.disconnect(from: device)
                    }
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Disconnect")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Initialize state from device when view appears
            isLocked = (bluetoothManager.deviceState == 1)
            print("🎬 View appeared - initial state: isLocked=\(isLocked), deviceState=\(bluetoothManager.deviceState)")
        }
        .onChange(of: bluetoothManager.deviceState) { newState in
            let newIsLocked = (newState == 1)
            print("🔄 Device state changed: \(newState) -> isLocked should be \(newIsLocked)")
            
            // Only update if different to avoid fighting with optimistic updates
            if isLocked != newIsLocked {
                print("⚠️ Correcting state mismatch: local=\(isLocked), device=\(newIsLocked)")
                isLocked = newIsLocked
            }
        }
    }
    
    // Helper computed property for state color
    private var stateColor: Color {
        switch bluetoothManager.deviceState {
        case 0:
            return .green
        case 1:
            return .red
        case 2:
            return .orange
        default:
            return .gray
        }
    }
    
    private func startHolding() {
        isHolding = true
        print("🟡 Started holding - current state: isLocked=\(isLocked)")
        
        // Use withAnimation for smooth progress
        withAnimation(.linear(duration: 1.0)) {
            holdProgress = 1.0
        }
        
        // Set timer for completion
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            if self.isHolding {
                self.completeHold()
            }
        }
    }
    
    private func stopHolding() {
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        print("🔴 Stopped holding early")
        
        // Animate progress back to 0
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    private func completeHold() {
        print("✅ Hold complete - current isLocked=\(isLocked)")
        
        // Send command based on current state - commands should CHANGE the state
        if isLocked {
            print("📤 Sending UNLOCK command (0x0F)")
            sendHexValue("0F") // Currently locked, so UNLOCK it
        } else {
            print("📤 Sending LOCK command (0x01)")
            sendHexValue("01") // Currently unlocked, so LOCK it
        }
        
        // Trigger haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        // Optimistically update the UI immediately
        isLocked.toggle()
        print("🔄 Optimistically toggled to isLocked=\(isLocked)")
        
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    private func sendHexValue(_ hexString: String) {
        var data = Data()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        bluetoothManager.sendData(data)
    }
}

// MARK: - Lock Button Component
struct LockButton: View {
    @Binding var isLocked: Bool
    let holdProgress: CGFloat
    
    var buttonColor: Color {
        // Button stays at its current state color, doesn't transition during hold
        return isLocked ? Color.red : Color.black
    }
    
    var body: some View {
        ZStack {
            // Background button
            RoundedRectangle(cornerRadius: 20)
                .fill(buttonColor)
                .frame(height: 80)
            
            // Progress overlay
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: geometry.size.width * holdProgress, height: 80)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            
            // Button content
            HStack(spacing: 15) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.title)
                Text(isLocked ? "Unlock" : "Lock")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
        }
        .shadow(radius: 5)
    }
}

// MARK: - Bluetooth Device Model
struct BluetoothDevice: Identifiable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    let rssi: Int
    var isConnected: Bool
}

// MARK: - Bluetooth Manager
class BluetoothManager: NSObject, ObservableObject {
    @Published var discoveredDevices: [BluetoothDevice] = []
    @Published var isScanning = false
    @Published var isBluetoothReady = false
    @Published var connectedDevice: BluetoothDevice?
    @Published var lastSentData: String = ""
    @Published var deviceState: UInt8 = 0  // Track device state
    
    private var centralManager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?  // For receiving notifications
    
    // Target service UUID: 0x183E - Still filtering by this!
    private let targetServiceUUID = CBUUID(string: "183E")
    
    // RSSI update throttling - only update once per second per device
    private var lastRSSIUpdate: [UUID: Date] = [:]
    private let rssiUpdateInterval: TimeInterval = 1.0
    
    // Device timeout - remove devices not seen in 5 seconds
    private let deviceTimeout: TimeInterval = 5.0
    private var staleDeviceTimer: Timer?
    
    // Connection timeout
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 10.0
    
    // Computed property for device state text
    var deviceStateText: String {
        switch deviceState {
        case 0:
            return "Unlocked"
        case 1:
            return "Locked"
        case 2:
            return "Alarming"
        default:
            return "Unknown (\(deviceState))"
        }
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard isBluetoothReady else { return }
        discoveredDevices.removeAll()
        lastRSSIUpdate.removeAll()  // Clear throttle timestamps
        
        // STILL FILTERING BY SERVICE UUID 0x183E
        centralManager.scanForPeripherals(
            withServices: [targetServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        print("Started scanning for 0x183E devices")
        
        // Start timer to remove stale devices
        staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.removeStaleDevices()
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        staleDeviceTimer?.invalidate()
        staleDeviceTimer = nil
    }
    
    func connect(to device: BluetoothDevice) {
        print("Connecting to: \(device.name)")
        centralManager.connect(device.peripheral, options: nil)
        
        // Start connection timeout timer
        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeout, repeats: false) { [weak self] _ in
            print("⏱️ Connection timeout for \(device.name)")
            self?.centralManager.cancelPeripheralConnection(device.peripheral)
            self?.connectionTimer = nil
        }
    }
    
    func disconnect(from device: BluetoothDevice) {
        centralManager.cancelPeripheralConnection(device.peripheral)
        connectedDevice = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        lastSentData = ""
        deviceState = 0
    }
    
    func sendData(_ data: Data) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedDevice?.peripheral else {
            print("No writable characteristic found")
            return
        }
        
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        lastSentData = "0x\(hexString) (\(data.count) bytes)"
        print("Sent: \(lastSentData)")
    }
    
    private func removeStaleDevices() {
        let now = Date()
        discoveredDevices.removeAll { device in
            guard let lastUpdate = lastRSSIUpdate[device.id] else {
                return true  // Remove if we have no update timestamp
            }
            let isStale = now.timeIntervalSince(lastUpdate) > deviceTimeout
            if isStale {
                print("🗑️ Removing stale device: \(device.name)")
                lastRSSIUpdate.removeValue(forKey: device.id)
            }
            return isStale
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothReady = central.state == .poweredOn
        if !isBluetoothReady {
            stopScanning()
            connectedDevice = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceID = peripheral.identifier
        let now = Date()
        
        // Check if we should update this device (throttle to once per second)
        if let lastUpdate = lastRSSIUpdate[deviceID] {
            if now.timeIntervalSince(lastUpdate) < rssiUpdateInterval {
                return  // Skip this update, too soon
            }
        }
        
        // Update the timestamp for this device
        lastRSSIUpdate[deviceID] = now
        
        // Use the actual device name from advertising data or peripheral
        let name = peripheral.name ?? "WatchDog"
        let device = BluetoothDevice(
            id: deviceID,
            name: name,
            peripheral: peripheral,
            rssi: RSSI.intValue,
            isConnected: false
        )
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
            print("Discovered: \(name) [\(deviceID.uuidString.prefix(8))]")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to: \(peripheral.name ?? "Unknown")")
        
        // Cancel connection timeout timer
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].isConnected = true
            connectedDevice = discoveredDevices[index]
        }
        
        stopScanning()
        
        peripheral.delegate = self
        peripheral.discoverServices([targetServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from: \(peripheral.name ?? "Unknown")")
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].isConnected = false
        }
        
        connectedDevice = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        lastSentData = ""
        deviceState = 0
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        
        // Cancel connection timeout timer
        connectionTimer?.invalidate()
        connectionTimer = nil
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("Found characteristic: \(characteristic.uuid)")
            print("  Properties: \(characteristic.properties)")
            
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                print("  ✅ This is writable! Ready to send data.")
            }
            
            // Subscribe to notifications
            if characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("  ✅ Subscribed to notifications!")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error reading characteristic: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else { return }
        
        // Update device state from received data
        if let firstByte = data.first {
            DispatchQueue.main.async {
                let oldState = self.deviceState
                self.deviceState = firstByte
                print("📥 Received device state: 0x\(String(format: "%02X", firstByte)) - \(self.deviceStateText) (was: 0x\(String(format: "%02X", oldState)))")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Write error: \(error.localizedDescription)")
        } else {
            print("✅ Data written successfully")
        }
    }
}

#Preview {
    ContentView()
}
