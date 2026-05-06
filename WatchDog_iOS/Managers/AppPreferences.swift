//
//  AppPreferences.swift
//  BluetoothTesting
//
//  Global app-level preferences distinct from per-device settings.
//

import Foundation
import Observation

@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    private let disconnectOnBackgroundKey = "watchdog_disconnect_on_background"

    /// When true, the app disconnects from the WatchDog after the user has
    /// backgrounded the app for more than 5 seconds. Default: true.
    var disconnectOnBackground: Bool {
        didSet { UserDefaults.standard.set(disconnectOnBackground, forKey: disconnectOnBackgroundKey) }
    }

    private init() {
        let ud = UserDefaults.standard
        if ud.object(forKey: disconnectOnBackgroundKey) != nil {
            self.disconnectOnBackground = ud.bool(forKey: disconnectOnBackgroundKey)
        } else {
            self.disconnectOnBackground = true
        }
    }
}
