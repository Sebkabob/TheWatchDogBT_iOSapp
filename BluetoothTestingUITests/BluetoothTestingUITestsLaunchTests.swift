//
//  BluetoothTestingUITestsLaunchTests.swift
//  BluetoothTestingUITests
//
//  Created by Sebastian Forenza on 10/30/25.
//

import Testing
import XCTest

struct BluetoothTestingUITestsLaunchTests {

    @Test func launch() async throws {
        let app = XCUIApplication()
        app.launch()
        #expect(app.state == .runningForeground)
    }
}
