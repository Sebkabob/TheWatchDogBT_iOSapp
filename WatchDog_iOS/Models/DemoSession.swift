//
//  DemoSession.swift
//  BluetoothTesting
//

import Foundation
import Observation

/// Holds the in-memory state for an active demo session. Created when the user
/// enters demo mode from the add-watchdog screen, discarded when they exit via
/// "Disconnect" or "Forget device". Nothing here is persisted — closing the
/// session resets every value to its default. The companion changes live in
/// `BluetoothManager.enterDemoMode()` and `SettingsManager.enterDemoMode()`,
/// which snapshot the real singletons, override their observable state, and
/// suppress all persistence so the demo's settings can flow through the same
/// UI bindings without ever touching disk.
@Observable
final class DemoSession {
    /// A unique, non-bonded UUID so DevicePageView's normal device-keyed
    /// reads (motion logs, custom name lookups) yield empty/default values.
    let deviceID: UUID = UUID()
    /// Editable name shown in the device header and settings field. Defaults
    /// to "DemoDog"; the user can rename it during the session, but the value
    /// dies with the session.
    var name: String = "DemoDog"
}
