//
//  NavigationStateManager.swift
//  BluetoothTesting
//
//  Created by Assistant on 2/9/26.
//

import Foundation
import Observation

@Observable
class NavigationStateManager {
    static let shared = NavigationStateManager()

    enum LastScreen: String, Codable {
        case deviceList
        case deviceControl
    }

    var lastScreen: LastScreen = .deviceList
    var lastDeviceID: UUID?
    
    private let lastScreenKey = "watchdog_last_screen"
    private let lastDeviceIDKey = "watchdog_last_device_id"
    
    private init() {
        loadState()
    }
    
    // MARK: - Save / Load
    
    func saveDeviceList() {
        lastScreen = .deviceList
        lastDeviceID = nil
        UserDefaults.standard.set(LastScreen.deviceList.rawValue, forKey: lastScreenKey)
        UserDefaults.standard.removeObject(forKey: lastDeviceIDKey)
        Log.info(.nav, "Saved · deviceList")
    }

    func saveDeviceControl(deviceID: UUID) {
        lastScreen = .deviceControl
        lastDeviceID = deviceID
        UserDefaults.standard.set(LastScreen.deviceControl.rawValue, forKey: lastScreenKey)
        UserDefaults.standard.set(deviceID.uuidString, forKey: lastDeviceIDKey)
        Log.info(.nav, "Saved · deviceControl [\(deviceID.uuidString.prefix(8))]")
    }
    
    private func loadState() {
        if let screenRaw = UserDefaults.standard.string(forKey: lastScreenKey),
           let screen = LastScreen(rawValue: screenRaw) {
            lastScreen = screen
        } else {
            lastScreen = .deviceList
        }
        
        if let idString = UserDefaults.standard.string(forKey: lastDeviceIDKey),
           let uuid = UUID(uuidString: idString) {
            // Only restore if the device is still bonded
            if BondManager.shared.isBonded(deviceID: uuid) {
                lastDeviceID = uuid
            } else {
                // Device was un-bonded, reset to list
                lastScreen = .deviceList
                lastDeviceID = nil
                Log.warn(.nav, "Last device no longer bonded · resetting to list")
            }
        }

        Log.info(.nav, "Loaded · \(lastScreen) device=\(lastDeviceID?.uuidString.prefix(8) ?? "none")")
    }
}
