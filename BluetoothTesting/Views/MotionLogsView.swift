//
//  MotionLogsView.swift
//  BluetoothTesting
//
//  Created by Assistant on 1/6/26.
//

import SwiftUI

struct MotionLogsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var motionLogManager = MotionLogManager.shared
    var bluetoothManager: BluetoothManager
    @State private var selectedDate: Date
    @State private var isSyncing = false
    @State private var syncProgress: Float = 0.0
    
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        // Initialize with most recent event date or today
        let mostRecentDate = MotionLogManager.shared.getMostRecentEventDate() ?? Date()
        _selectedDate = State(initialValue: mostRecentDate)
    }
    
    private var filteredEvents: [MotionEvent] {
        motionLogManager.getEvents(for: selectedDate)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Calendar Section
            VStack(spacing: 0) {
                CalendarView(
                    selectedDate: $selectedDate,
                    eventsPerDay: getEventsPerDay()
                )
                .padding(.horizontal)
                .padding(.top, 16)
                
                Divider()
                    .padding(.top, 16)
            }
            .background(Color(.systemBackground))
            
            // Events List Section
            if filteredEvents.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No Motion Events")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(selectedDateText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                List {
                    Section(header:
                        HStack {
                            Text(selectedDateHeaderText)
                            Spacer()
                            Text("\(filteredEvents.count) event\(filteredEvents.count == 1 ? "" : "s")")
                        }
                        .font(.subheadline)
                    ) {
                        ForEach(filteredEvents) { event in
                            MotionEventRow(event: event)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Motion Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("\(Int(syncProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if bluetoothManager.connectedDevice != nil {
                    Button(action: {
                        startSync()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Sync")
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if !motionLogManager.motionEvents.isEmpty {
                    Menu {
                        Button(role: .destructive, action: {
                            motionLogManager.clearAllEvents()
                        }) {
                            Label("Clear All Events", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var selectedDateText: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "No events recorded today"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "No events on \(formatter.string(from: selectedDate))"
        }
    }
    
    private var selectedDateHeaderText: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: selectedDate)
        }
    }
    
    private func getEventsPerDay() -> [Date: Int] {
        var eventsPerDay: [Date: Int] = [:]
        let calendar = Calendar.current
        
        for event in motionLogManager.motionEvents {
            let dayStart = calendar.startOfDay(for: event.timestamp)
            eventsPerDay[dayStart, default: 0] += 1
        }
        
        return eventsPerDay
    }
    
    private func startSync() {
        guard bluetoothManager.connectedDevice != nil else {
            print("❌ Not connected to device")
            return
        }
        
        print("📤 Requesting motion log count...")
        isSyncing = true
        syncProgress = 0.0
        
        // Send command to request log count
        let command = Data([0xF0])  // CMD_REQUEST_LOG_COUNT
        bluetoothManager.sendData(command)
        
        // TODO: For now, just show syncing state for 2 seconds
        // When you replace with BluetoothManager_Updated.swift, the full sync will work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isSyncing = false
            syncProgress = 1.0
        }
    }
}

// MARK: - Calendar View
struct CalendarView: View {
    @Binding var selectedDate: Date
    let eventsPerDay: [Date: Int]
    
    @State private var currentMonth: Date = Date()
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 12) {
            // Month/Year Header with navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                
                Spacer()
                
                Text(dateFormatter.string(from: currentMonth))
                    .font(.headline)
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            
            // Day labels
            HStack(spacing: 0) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(Array(getDaysInMonth().enumerated()), id: \.offset) { index, date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            eventCount: eventsPerDay[calendar.startOfDay(for: date)] ?? 0
                        ) {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                selectedDate = date
                            }
                        }
                    } else {
                        // Empty cell for padding
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func getDaysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday else {
            return []
        }
        
        var days: [Date?] = []
        
        // Add empty cells for days before month starts
        let emptyCells = (firstWeekday - calendar.firstWeekday + 7) % 7
        days.append(contentsOf: Array(repeating: nil, count: emptyCells))
        
        // Add all days in month
        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }
    
    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
}

// MARK: - Day Cell
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let eventCount: Int
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                    .foregroundColor(textColor)
                
                if eventCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 18, height: 18)
                        
                        Text("\(eventCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    Spacer()
                        .frame(height: 18)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else {
            return .primary
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else {
            return Color(.systemGray6)
        }
    }
}

// MARK: - Motion Event Row
struct MotionEventRow: View {
    let event: MotionEvent
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.timestamp)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: event.eventType.icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            // Event details
            VStack(alignment: .leading, spacing: 4) {
                Text(event.eventType.displayName)
                    .font(.headline)
                
                Text(timeString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Alarm indicator
            if event.alarmSounded {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                    Text("Alarm")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var iconColor: Color {
        switch event.eventType {
        case .unknown: return .gray
        case .lightMovement: return .blue
        case .moderateMovement: return .orange
        case .severeMovement: return .red
        case .tamper: return .purple
        }
    }
}

#Preview {
    NavigationView {
        MotionLogsView(bluetoothManager: BluetoothManager())
    }
}
