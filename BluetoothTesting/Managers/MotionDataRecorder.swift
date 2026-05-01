//
//  MotionDataRecorder.swift
//  BluetoothTesting
//

import Foundation
import Observation

@Observable
class MotionDataRecorder {
    static let shared = MotionDataRecorder()

    var isRecording = false
    var sampleCount = 0

    private static let sampleInterval: TimeInterval = 0.04

    private var samples: [(x: Int, y: Int, z: Int)] = []
    private var startDate: Date?
    private var lastSampleTime: Date?

    private init() {}

    func startRecording() {
        samples.removeAll()
        sampleCount = 0
        startDate = Date()
        lastSampleTime = nil
        isRecording = true
    }

    func addSample(x: Float, y: Float, z: Float) {
        guard isRecording else { return }
        let now = Date()
        if let last = lastSampleTime, now.timeIntervalSince(last) < Self.sampleInterval {
            return
        }
        lastSampleTime = now
        samples.append((x: Int((x * 1000).rounded()),
                        y: Int((y * 1000).rounded()),
                        z: Int((z * 1000).rounded())))
        sampleCount = samples.count
    }

    func stopRecording() -> URL? {
        isRecording = false
        guard !samples.isEmpty, let start = startDate else { return nil }
        return writeCSV(startDate: start)
    }

    private func writeCSV(startDate: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "MLC_\(formatter.string(from: startDate)).csv"

        let dir = FileManager.default.temporaryDirectory
        let fileURL = dir.appendingPathComponent(fileName)

        var csv = "acc_x[mg],acc_y[mg],acc_z[mg]\n"

        for s in samples {
            csv += "\(s.x),\(s.y),\(s.z)\n"
        }

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            print("📝 CSV saved: \(fileURL.lastPathComponent) (\(samples.count) samples)")
            return fileURL
        } catch {
            print("❌ Failed to write CSV: \(error)")
            return nil
        }
    }
}
