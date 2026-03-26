//
//  BluetoothTestingUITests.swift
//  BluetoothTestingUITests
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Testing
import XCTest

struct BluetoothTestingUITests {

    @Test func appLaunches() async throws {
        let app = XCUIApplication()
        app.launch()
        #expect(app.state == .runningForeground)
    }
}
