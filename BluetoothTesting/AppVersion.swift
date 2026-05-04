//
//  AppVersion.swift
//  BluetoothTesting
//

import Foundation

/// App version — bumped per the rules in CLAUDE.md ("App Version" section).
/// Format: V<major>.<main>.<v2>. Display string includes leading-zero v2.
enum AppVersion {
    static let major: Int = 1
    static let main:  Int = 11
    static let v2:    Int = 36

    /// "V1.0.00" — note the two-digit V2 field for display.
    static var displayString: String {
        String(format: "V%d.%d.%02d", major, main, v2)
    }
}
