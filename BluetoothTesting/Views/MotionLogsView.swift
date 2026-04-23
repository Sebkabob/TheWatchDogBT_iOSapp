//
//  MotionLogsView.swift
//  BluetoothTesting
//
//  Created by Assistant on 1/6/26.
//

import SwiftUI

struct MotionLogsView: View {
    @Environment(\.dismiss) var dismiss
    var bluetoothManager: BluetoothManager
    let deviceID: UUID
    private let motionLogManager = MotionLogManager.shared
    @State private var selectedDate: Date
    @State private var refreshID = UUID()
    @State private var showMonthYearPicker = false
    @State private var showClearAllConfirmation = false
    @State private var showClearTodayConfirmation = false

    @AppStorage("skipClearEventsConfirmation") private var skipConfirmation = false

    init(bluetoothManager: BluetoothManager, deviceID: UUID) {
        self.bluetoothManager = bluetoothManager
        self.deviceID = deviceID
        _selectedDate = State(initialValue: Date())
    }

    private var filteredEvents: [MotionEvent] {
        motionLogManager.getEvents(for: selectedDate, deviceID: deviceID)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Calendar Section
            VStack(spacing: 0) {
                CalendarView(
                    selectedDate: $selectedDate,
                    eventsPerDay: getEventsPerDay(),
                    onMonthTapped: {
                        showMonthYearPicker = true
                    }
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
        .id(refreshID)
        .navigationTitle("Motion Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !Calendar.current.isDate(selectedDate, equalTo: Date(), toGranularity: .month) {
                    Button {
                        withAnimation {
                            selectedDate = Date()
                        }
                    } label: {
                        Text("Today")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !motionLogManager.eventsForDevice(deviceID).isEmpty {
                    Menu {
                        if !motionLogManager.getEvents(for: Date(), deviceID: deviceID).isEmpty {
                            Button(role: .destructive, action: {
                                if skipConfirmation {
                                    motionLogManager.clearEventsForDate(Date(), deviceID: deviceID)
                                } else {
                                    showClearTodayConfirmation = true
                                }
                            }) {
                                Label("Clear Today's Events", systemImage: "calendar.badge.minus")
                            }
                        }

                        Button(role: .destructive, action: {
                            if skipConfirmation {
                                motionLogManager.clearAllEvents(for: deviceID)
                            } else {
                                showClearAllConfirmation = true
                            }
                        }) {
                            Label("Clear All Events", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Clear All Events?", isPresented: $showClearAllConfirmation) {
            Button("OK", role: .destructive) {
                motionLogManager.clearAllEvents(for: deviceID)
            }
            Button("No", role: .cancel) { }
            Button("Don't Show This Again", role: .destructive) {
                skipConfirmation = true
                motionLogManager.clearAllEvents(for: deviceID)
            }
        } message: {
            Text("Are you sure you want to clear all events?")
        }
        .alert("Clear Today's Events?", isPresented: $showClearTodayConfirmation) {
            Button("OK", role: .destructive) {
                motionLogManager.clearEventsForDate(Date(), deviceID: deviceID)
            }
            Button("No", role: .cancel) { }
            Button("Don't Show This Again", role: .destructive) {
                skipConfirmation = true
                motionLogManager.clearEventsForDate(Date(), deviceID: deviceID)
            }
        } message: {
            Text("Are you sure you want to clear today's events?")
        }
        .sheet(isPresented: $showMonthYearPicker) {
            MonthYearPickerSheet(
                selectedDate: $selectedDate,
                eventsPerMonth: getEventsPerMonth()
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            bluetoothManager.startMotionLogPolling()
        }
        .onDisappear {
            bluetoothManager.stopMotionLogPolling()
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

        for event in motionLogManager.eventsForDevice(deviceID) {
            let dayStart = calendar.startOfDay(for: event.timestamp)
            eventsPerDay[dayStart, default: 0] += 1
        }

        return eventsPerDay
    }

    /// Returns event counts keyed by the first day of each month
    private func getEventsPerMonth() -> [Date: Int] {
        var eventsPerMonth: [Date: Int] = [:]
        let calendar = Calendar.current

        for event in motionLogManager.eventsForDevice(deviceID) {
            let components = calendar.dateComponents([.year, .month], from: event.timestamp)
            if let monthStart = calendar.date(from: components) {
                eventsPerMonth[monthStart, default: 0] += 1
            }
        }

        return eventsPerMonth
    }
}

// MARK: - Month/Year Picker Sheet
struct MonthYearPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedDate: Date
    let eventsPerMonth: [Date: Int]
    
    @State private var selectedMonth: Int
    @State private var selectedYear: Int
    
    private let calendar = Calendar.current
    private let months = Calendar.current.monthSymbols
    
    // Year range: earliest event year to current year
    private var years: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        let earliestYear = eventsPerMonth.keys
            .map { calendar.component(.year, from: $0) }
            .min() ?? currentYear
        return Array(earliestYear...currentYear)
    }
    
    init(selectedDate: Binding<Date>, eventsPerMonth: [Date: Int]) {
        self._selectedDate = selectedDate
        self.eventsPerMonth = eventsPerMonth
        let cal = Calendar.current
        _selectedMonth = State(initialValue: cal.component(.month, from: selectedDate.wrappedValue))
        _selectedYear = State(initialValue: cal.component(.year, from: selectedDate.wrappedValue))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Event count for selected month
                let count = eventCountForSelection()
                if count > 0 {
                    Text("\(count) event\(count == 1 ? "" : "s") in \(months[selectedMonth - 1]) \(String(selectedYear))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                } else {
                    Text("No events in \(months[selectedMonth - 1]) \(String(selectedYear))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                
                // Two side-by-side wheels
                HStack(spacing: 0) {
                    // Month picker
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { month in
                            let monthName = months[month - 1]
                            let count = eventCountFor(month: month, year: selectedYear)
                            HStack {
                                Text(monthName)
                                if count > 0 {
                                    Text("(\(count))")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    
                    // Year picker
                    Picker("Year", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            let count = eventCountFor(year: year)
                            HStack {
                                Text(String(year))
                                if count > 0 {
                                    Text("(\(count))")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Jump to Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Go") {
                        applySelection()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func applySelection() {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        components.day = 1
        
        if let newDate = calendar.date(from: components) {
            // If the selected month/year is the current month, jump to today
            let now = Date()
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            
            if selectedMonth == currentMonth && selectedYear == currentYear {
                selectedDate = now
            } else {
                selectedDate = newDate
            }
        }
    }
    
    private func eventCountForSelection() -> Int {
        return eventCountFor(month: selectedMonth, year: selectedYear)
    }
    
    private func eventCountFor(month: Int, year: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        if let monthStart = calendar.date(from: components) {
            return eventsPerMonth[monthStart] ?? 0
        }
        return 0
    }
    
    private func eventCountFor(year: Int) -> Int {
        var total = 0
        for month in 1...12 {
            total += eventCountFor(month: month, year: year)
        }
        return total
    }
}

// MARK: - Calendar View
struct CalendarView: View {
    @Binding var selectedDate: Date
    let eventsPerDay: [Date: Int]
    var onMonthTapped: (() -> Void)? = nil
    
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
                
                // Tappable month/year label
                Button(action: {
                    onMonthTapped?()
                }) {
                    HStack(spacing: 4) {
                        Text(dateFormatter.string(from: currentMonth))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
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
                ForEach(getDaysInMonth(), id: \.self) { date in
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
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        // Sync currentMonth when selectedDate changes (e.g. from picker)
        .onChange(of: selectedDate) { _, newDate in
            let selectedMonthStart = calendar.dateInterval(of: .month, for: newDate)?.start
            let currentMonthStart = calendar.dateInterval(of: .month, for: currentMonth)?.start
            if selectedMonthStart != currentMonthStart {
                currentMonth = newDate
            }
        }
    }
    
    private func getDaysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday else {
            return []
        }
        
        var days: [Date?] = []
        
        let emptyCells = (firstWeekday - calendar.firstWeekday + 7) % 7
        days.append(contentsOf: Array(repeating: nil, count: emptyCells))
        
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
            Image(systemName: event.eventType.icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.eventType.displayName)
                    .font(.headline)
                
                Text(timeString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
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
        case .none:         return .gray
        case .inMotion:     return .orange
        case .shaken:       return .red
        case .impact:       return .red
        case .freefall:     return .purple
        case .tilted:       return .yellow
        case .doorOpening:  return .orange
        case .doorClosing:  return .blue
        }
    }
}

#Preview {
    NavigationStack {
        MotionLogsView(bluetoothManager: BluetoothManager(), deviceID: UUID())
    }
}
