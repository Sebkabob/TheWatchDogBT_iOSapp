//
//  DebugGraphs.swift
//  BluetoothTesting
//

import SwiftUI

struct DebugInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 9))
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .monospaced()
        }
    }
}

struct VoltageGraph: View {
    let history: [(date: Date, value: Double)]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let now = Date()
            let validHistory = history.filter { now.timeIntervalSince($0.date) >= 2.0 }
            let dataMin = validHistory.map { $0.value }.min() ?? 3.7
            let dataMax = validHistory.map { $0.value }.max() ?? 4.2
            let minY = max(2.5, dataMin - 0.1)
            let maxY = min(4.2, dataMax + 0.1)
            let rangeY = maxY - minY

            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color(.systemGray6))
                VStack(spacing: 0) { ForEach(0..<3) { _ in Divider().background(Color.gray.opacity(0.3)); Spacer() } }
                if validHistory.count > 1 {
                    let maxTimeRange: TimeInterval = 180
                    let oldestTime = validHistory.first?.date ?? now
                    let actualTimeRange = min(now.timeIntervalSince(oldestTime), maxTimeRange)
                    Path { path in
                        for (index, point) in validHistory.enumerated() {
                            let clampedValue = max(minY, min(maxY, point.value))
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / actualTimeRange) * width)
                            let normalizedValue = rangeY > 0 ? (clampedValue - minY) / rangeY : 0.5
                            let y = height - (CGFloat(normalizedValue) * height)
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }.stroke(Color.purple, lineWidth: 1.5)
                }
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", maxY)).font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", (minY + maxY) / 2)).font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", minY)).font(.system(size: 6)).foregroundColor(.secondary)
                }.padding(.leading, 2)
            }.cornerRadius(4)
        }
    }
}

struct CurrentGraph: View {
    let history: [(date: Date, value: Double)]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let now = Date()
            let validHistory = history.filter { now.timeIntervalSince($0.date) >= 2.0 }
            let dataMin = validHistory.map { $0.value }.min() ?? -50
            let dataMax = validHistory.map { $0.value }.max() ?? 50
            let minY = max(-300, dataMin - 10)
            let maxY = min(300, dataMax + 10)
            let rangeY = maxY - minY

            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color(.systemGray6))
                VStack(spacing: 0) { ForEach(0..<3) { _ in Divider().background(Color.gray.opacity(0.3)); Spacer() } }
                if minY <= 0 && maxY >= 0 {
                    let zeroY = height - (CGFloat((0 - minY) / rangeY) * height)
                    Path { path in path.move(to: CGPoint(x: 0, y: zeroY)); path.addLine(to: CGPoint(x: width, y: zeroY)) }
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                }
                if validHistory.count > 1 {
                    let maxTimeRange: TimeInterval = 90
                    let oldestTime = validHistory.first?.date ?? now
                    let actualTimeRange = min(now.timeIntervalSince(oldestTime), maxTimeRange)
                    Path { path in
                        for (index, point) in validHistory.enumerated() {
                            let clampedValue = max(minY, min(maxY, point.value))
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / actualTimeRange) * width)
                            let normalizedValue = rangeY > 0 ? (clampedValue - minY) / rangeY : 0.5
                            let y = height - (CGFloat(normalizedValue) * height)
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }.stroke(lineColor, lineWidth: 1.5)
                }
                VStack(spacing: 0) {
                    Text(String(format: "%.0f", maxY)).font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", (minY + maxY) / 2)).font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", minY)).font(.system(size: 6)).foregroundColor(.secondary)
                }.padding(.leading, 2)
            }.cornerRadius(4)
        }
    }

    private var lineColor: Color {
        guard let lastValue = history.last?.value else { return .blue }
        return lastValue > 0 ? .green : .blue
    }
}

struct SOCGraph: View {
    let history: [(date: Date, value: Double)]
    let minSOC: Double
    let maxSOC: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let now = Date()
            let validHistory = history.filter { now.timeIntervalSince($0.date) >= 2.0 }
            let dataMin = validHistory.map { $0.value }.min() ?? minSOC
            let dataMax = validHistory.map { $0.value }.max() ?? maxSOC
            let minY = max(0, dataMin - 2)
            let maxY = min(100, dataMax + 2)
            let rangeY = maxY - minY

            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color(.systemGray6))
                VStack(spacing: 0) { ForEach(0..<3) { _ in Divider().background(Color.gray.opacity(0.3)); Spacer() } }
                if validHistory.count > 1 {
                    let maxTimeRange: TimeInterval = 180
                    let oldestTime = validHistory.first?.date ?? now
                    let actualTimeRange = min(now.timeIntervalSince(oldestTime), maxTimeRange)
                    Path { path in
                        for (index, point) in validHistory.enumerated() {
                            let clampedValue = max(minY, min(maxY, point.value))
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / actualTimeRange) * width)
                            let normalizedValue = rangeY > 0 ? (clampedValue - minY) / rangeY : 0.5
                            let y = height - (CGFloat(normalizedValue) * height)
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }.stroke(Color.green, lineWidth: 1.5)
                }
                VStack(spacing: 0) {
                    Text("\(Int(maxY))").font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int((minY + maxY) / 2))").font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(minY))").font(.system(size: 6)).foregroundColor(.secondary)
                }.padding(.leading, 2)
            }.cornerRadius(4)
        }
    }
}

struct AccelGraph: View {
    let history: [(date: Date, value: Double)]
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.01)) { timeline in
            let now = timeline.date
            AccelGraphContent(history: history, color: color, now: now)
        }
    }
}

private struct AccelGraphContent: View {
    let history: [(date: Date, value: Double)]
    let color: Color
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let validHistory = history.filter { now.timeIntervalSince($0.date) <= 15.0 && now.timeIntervalSince($0.date) >= 0.0 }
            let dataMin = validHistory.map { $0.value }.min() ?? -1.0
            let dataMax = validHistory.map { $0.value }.max() ?? 1.0
            let margin = max(0.1, (dataMax - dataMin) * 0.1)
            let minY = dataMin - margin
            let maxY = dataMax + margin
            let rangeY = maxY - minY

            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color(.systemGray6))
                VStack(spacing: 0) { ForEach(0..<3) { _ in Divider().background(Color.gray.opacity(0.3)); Spacer() } }
                if validHistory.count > 1 {
                    let maxTimeRange: TimeInterval = 15
                    Path { path in
                        for (index, point) in validHistory.enumerated() {
                            let clampedValue = max(minY, min(maxY, point.value))
                            let timeOffset = now.timeIntervalSince(point.date)
                            let x = width - (CGFloat(timeOffset / maxTimeRange) * width)
                            let normalizedValue = rangeY > 0 ? (clampedValue - minY) / rangeY : 0.5
                            let y = height - (CGFloat(normalizedValue) * height)
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }.stroke(color, lineWidth: 1.5)
                }
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", maxY)).font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", (minY + maxY) / 2)).font(.system(size: 6)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", minY)).font(.system(size: 6)).foregroundColor(.secondary)
                }.padding(.leading, 2)
            }.cornerRadius(4)
        }
    }
}
