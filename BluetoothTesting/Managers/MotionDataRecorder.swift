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

    private var samples: [(timestamp: Int, x: Float, y: Float, z: Float)] = []
    private var startDate: Date?
    private var recordingStartTime: Date?

    private init() {}

    func startRecording() {
        samples.removeAll()
        sampleCount = 0
        startDate = Date()
        recordingStartTime = Date()
        isRecording = true
    }

    func addSample(x: Float, y: Float, z: Float) {
        guard isRecording, let start = recordingStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        samples.append((timestamp: elapsed, x: x, y: y, z: z))
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

        var csv = "# Sensor: LIS2DUX12\n"
        csv += "# Columns: [Acceleration X, Acceleration Y, Acceleration Z]\n"
        csv += "Timestamp,AccX,AccY,AccZ\n"

        for s in samples {
            csv += "\(s.timestamp),\(String(format: "%.4f", s.x)),\(String(format: "%.4f", s.y)),\(String(format: "%.4f", s.z))\n"
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
