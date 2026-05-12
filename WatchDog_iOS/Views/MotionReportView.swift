//
//  MotionReportView.swift
//  WatchDog_iOS
//
//  Created by Sebastian Forenza 2026.
//
//  Replaces the legacy MotionLogsView. Surfaces motion data as sessions
//  (bookended by SESSION_START / SESSION_END firmware markers) rather than
//  a flat event timeline.
//
//  Three lenses on the same data:
//    Feed     — newest-first session cards with sticky date headers
//    Calendar — month grid; tap a day to filter the feed
//    Map      — placeholder until lock-location capture ships
//
//  The detail screen (SessionDetailView) pushes onto the same NavigationStack.
//

import SwiftUI

struct MotionReportView: View {
    @Environment(\.dismiss) private var dismiss
    let bluetoothManager: BluetoothManager
    let deviceID: UUID

    private let motionLogManager = MotionLogManager.shared
    private let locationStore = SessionLocationStore.shared

    @State private var selectedTab: Tab = .feed
    @State private var calendarSelectedDate: Date = Date()
    @State private var showClearAllConfirmation = false
    @State private var showMonthYearPicker = false
    /// Day-keyed set of feed sections the user has tapped "Show more"
    /// on. Empty by default — days with >2 sessions render the first
    /// two and an expand button until the user opts in.
    @State private var expandedFeedDays: Set<Date> = []
    @AppStorage("skipClearEventsConfirmation") private var skipConfirmation = false

    enum Tab: String, CaseIterable, Identifiable {
        case feed
        case calendar
        case map
        var id: String { rawValue }
        var label: String {
            switch self {
            case .feed:     return "Feed"
            case .calendar: return "Calendar"
            case .map:      return "Map"
            }
        }
    }

    /// Recomputed on every body render directly from
    /// `MotionLogManager.shared.motionEvents`. SwiftUI's Observation
    /// framework tracks the read and re-renders when motion events change
    /// (e.g. while a drain is in progress and the polling timer is
    /// pulling fresh data). Pre-filtering by deviceID before parsing
    /// keeps each device's session boundaries from getting cross-mixed
    /// when multiple WatchDogs share the same iOS install.
    private var deviceSessions: [MotionSession] {
        let myEvents = motionLogManager.motionEvents.filter { $0.deviceID == deviceID }
        return MotionSessionParser.parse(
            events: myEvents,
            currentlyArmed: (bluetoothManager.deviceState & 0x01) != 0,
            lastDisarmAt: nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            navHeader

            tabSelector
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)

            Group {
                switch selectedTab {
                case .feed:     feedTab
                case .calendar: calendarTab
                case .map:      mapTab
                }
            }
        }
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { onMotionReportAppeared() }
        .onDisappear { onMotionReportDisappeared() }
        .alert("Clear All Sessions?", isPresented: $showClearAllConfirmation) {
            Button("OK", role: .destructive) {
                clearAllSessionsBothSides()
            }
            Button("No", role: .cancel) { }
            Button("Don't Show This Again", role: .destructive) {
                skipConfirmation = true
                clearAllSessionsBothSides()
            }
        } message: {
            Text("This will remove every session and motion event for this device.")
        }
    }

    // MARK: - Header

    /// Back button anchored left, optional menu anchored right, title
    /// dropped on top via overlay so it stays dead-centered regardless of
    /// what the side widgets weigh. Mirrors the wireframe.
    private var navHeader: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.body)
                .foregroundColor(.accentColor)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }

            Spacer()

            if !deviceSessions.isEmpty {
                Menu {
                    // Calendar tab gets per-day / per-week / per-month
                    // clear options keyed off the currently-selected day.
                    // Feed and Map tabs only get the global wipe — there's
                    // no "selected" context there to scope a partial clear.
                    if selectedTab == .calendar {
                        Button(role: .destructive) {
                            clearForDay(calendarSelectedDate)
                        } label: {
                            Label(dayClearLabel(for: calendarSelectedDate),
                                  systemImage: "calendar.badge.minus")
                        }
                        Button(role: .destructive) {
                            clearForWeek(containing: calendarSelectedDate)
                        } label: {
                            Label(weekClearLabel(for: calendarSelectedDate),
                                  systemImage: "calendar.badge.minus")
                        }
                        Button(role: .destructive) {
                            clearForMonth(containing: calendarSelectedDate)
                        } label: {
                            Label(monthClearLabel(for: calendarSelectedDate),
                                  systemImage: "calendar.badge.minus")
                        }
                        Divider()
                    }
                    Button(role: .destructive) {
                        if skipConfirmation {
                            clearAllSessionsBothSides()
                        } else {
                            showClearAllConfirmation = true
                        }
                    } label: {
                        Label("Clear All Sessions", systemImage: "trash")
                    }
                } label: {
                    // Larger hit target than the bare 17pt SF Symbol. The
                    // icon stays the same size; we just give it real
                    // padding so the tappable area matches the back
                    // button's visual weight.
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
            } else {
                Color.clear.frame(width: 44, height: 32)
            }
        }
        .overlay {
            Text("Motion Report")
                .font(.headline)
        }
        .padding(.horizontal, 16)
        // Slightly more breathing room above "Motion Report" — was
        // hugging the sheet's top edge / system status bar.
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Tab selector

    /// Custom segmented control — same look as `AnimatedSegmentedControl`
    /// in the sensitivity settings, but with a drag gesture layered on
    /// top so you can slide your finger across the pill and the
    /// selection follows. iOS's built-in `.pickerStyle(.segmented)`
    /// doesn't support drag-to-change, only tap, which was the "I have
    /// to tap multiple times" report.
    private var tabSelector: some View {
        SlidingSegmentedControl(
            selection: $selectedTab,
            options: Tab.allCases.map { $0 },
            label: { $0.label }
        )
    }

    // MARK: - Feed

    @ViewBuilder
    private var feedTab: some View {
        if deviceSessions.isEmpty {
            emptyState(
                icon: "lock.shield",
                title: "No sessions yet",
                message: "Lock your WatchDog to start the first session."
            )
        } else {
            feedScrollContent
        }
    }

    /// Pulled out of `feedTab` because the combined expression (Group +
    /// ScrollView + LazyVStack + nested ForEach with conditional rows
    /// + animation closure) tipped Swift's type-checker over its
    /// inference budget. Splitting the body into named subviews keeps
    /// each piece simple enough for the compiler to chew through.
    private var feedScrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                feedActiveCard
                let closed = deviceSessions.filter { $0.status != .active }
                let grouped = groupedByDay(closed)
                ForEach(Array(grouped), id: \.key) { day, group in
                    feedDaySection(day: day, group: group)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var feedActiveCard: some View {
        if let active = deviceSessions.first(where: { $0.status == .active }) {
            ActiveSessionCard(session: active, deviceID: deviceID)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private func feedDaySection(day: Date, group: [MotionSession]) -> some View {
        SectionHeader(text: sectionTitle(for: day))
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 8)

        let isExpanded = expandedFeedDays.contains(day)
        let visible: [MotionSession] = isExpanded ? group : Array(group.prefix(2))

        ForEach(visible) { session in
            feedSessionRow(session: session)
        }

        if !isExpanded && group.count > 2 {
            FeedExpandRow(hiddenCount: group.count - 2) {
                // Discard `insert`'s tuple return so the closure's
                // inferred type stays `() -> Void` to match
                // FeedExpandRow.onTap. Without the explicit `_ =`,
                // Swift propagates the (Bool, Date) tuple all the
                // way up and the compiler rejects the call.
                withAnimation(.easeInOut(duration: 0.15)) {
                    _ = expandedFeedDays.insert(day)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func feedSessionRow(session: MotionSession) -> some View {
        NavigationLink {
            SessionDetailView(session: session)
        } label: {
            SessionCard(session: session)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .buttonStyle(.plain)
    }

    /// Bucket sessions by their start day (or distantPast for unknown-start).
    /// `OrderedPairs` keeps section order newest-first.
    private func groupedByDay(_ sessions: [MotionSession]) -> [(key: Date, value: [MotionSession])] {
        let cal = Calendar.current
        var buckets: [Date: [MotionSession]] = [:]
        for session in sessions {
            let day: Date
            if let start = session.startedAt {
                day = cal.startOfDay(for: start)
            } else {
                day = .distantPast
            }
            buckets[day, default: []].append(session)
        }
        return buckets
            .map { ($0.key, $0.value) }
            .sorted { $0.0 > $1.0 }
    }

    private func sectionTitle(for day: Date) -> String {
        let cal = Calendar.current
        if day == .distantPast { return "UNKNOWN DATE" }
        if cal.isDateInToday(day)     { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: day).uppercased()
    }

    // MARK: - Calendar

    private var calendarTab: some View {
        VStack(spacing: 0) {
            CalendarMonthGrid(
                selectedDate: $calendarSelectedDate,
                dotsByDay: cachedDotsByDay,
                onMonthLabelTap: { showMonthYearPicker = true }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            let dayList = sessionsOn(calendarSelectedDate)

            if dayList.isEmpty {
                emptyState(
                    icon: "calendar.badge.exclamationmark",
                    title: "No sessions",
                    message: dayLabel(calendarSelectedDate)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        SectionHeader(text: dayLabel(calendarSelectedDate).uppercased())
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                        ForEach(dayList) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionCard(session: session)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showMonthYearPicker) {
            MonthYearPicker(selectedDate: $calendarSelectedDate,
                            sessionsByMonth: sessionsByMonth())
                .presentationDetents([.medium])
        }
    }

    /// Worst-status dot per day. The calendar redraws often — particularly
    /// while the active-session card's 1s timer fires — and rebuilding
    /// this dictionary every redraw was the sluggishness behind the
    /// "tap a date and it sometimes doesn't go" report. Computed once
    /// per body pass against the current sessions snapshot; SwiftUI's
    /// observation tracking handles invalidation automatically.
    private var cachedDotsByDay: [Date: SessionStatus] {
        let cal = Calendar.current
        var dots: [Date: SessionStatus] = [:]
        for session in deviceSessions {
            guard let start = session.startedAt else { continue }
            let day = cal.startOfDay(for: start)
            dots[day] = worst(dots[day], session.status)
        }
        return dots
    }

    /// Count-per-month for the picker, keyed by first-of-month dates.
    private func sessionsByMonth() -> [Date: Int] {
        let cal = Calendar.current
        var counts: [Date: Int] = [:]
        for session in deviceSessions {
            guard let start = session.startedAt else { continue }
            let comps = cal.dateComponents([.year, .month], from: start)
            if let monthStart = cal.date(from: comps) {
                counts[monthStart, default: 0] += 1
            }
        }
        return counts
    }

    private func worst(_ a: SessionStatus?, _ b: SessionStatus) -> SessionStatus {
        guard let a = a else { return b }
        let order: [SessionStatus] = [.peaceful, .disturbed, .incomplete, .active, .alarmed]
        let ai = order.firstIndex(of: a) ?? 0
        let bi = order.firstIndex(of: b) ?? 0
        return ai > bi ? a : b
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    // MARK: - Map

    @ViewBuilder
    private var mapTab: some View {
        let store = SessionLocationStore.shared
        let pinned = deviceSessions.compactMap { session -> SessionMapPin? in
            guard let loc = store.location(for: session.id) else { return nil }
            return SessionMapPin(session: session, location: loc)
        }

        switch store.authorizationStatus {
        case .denied, .restricted:
            emptyState(
                icon: "location.slash",
                title: "Location access disabled",
                message: "Open Settings → Privacy → Location and turn on access for WatchDog if you'd like sessions pinned on the map."
            )
        case .notDetermined:
            emptyState(
                icon: "location",
                title: "Location not yet enabled",
                message: "Hold to lock once with location enabled to start pinning sessions on the map."
            )
        default:
            if pinned.isEmpty {
                emptyState(
                    icon: "mappin.slash",
                    title: "No pinned sessions yet",
                    message: "Sessions will appear here as pins once you lock the device with location enabled."
                )
            } else {
                SessionsMapView(pins: pinned)
            }
        }
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Clear

    /// Events that must survive every "Clear …" path — the active
    /// session's SESSION_START marker plus all motion events bundled into
    /// it. The user explicitly asked that an active session be immune:
    /// it's an in-progress lock, not historical data, and wiping its
    /// firmware-side companion mid-session would break the SESSION_END
    /// pairing when the device eventually unlocks.
    ///
    /// We deliberately do NOT also send CMD_CLEAR_LOG suppression: even
    /// though "Clear All Sessions" wipes the firmware ring (including
    /// the active SESSION_START there), iOS still holds the SESSION_START
    /// in its own cache. When the user later disarms, the firmware logs
    /// a fresh SESSION_END, it drains to iOS, the parser pairs it with
    /// the locally-cached SESSION_START, and the session closes
    /// normally. The firmware ring being temporarily out of sync with
    /// iOS is harmless — the eventual SESSION_END is what matters.
    private func protectedEventIDs() -> Set<UUID> {
        guard let active = deviceSessions
            .first(where: { $0.status == .active }) else {
            return []
        }
        var ids: Set<UUID> = [active.id]            // SESSION_START
        ids.formUnion(active.events.map { $0.id })  // motion events inside
        return ids
    }

    private func clearAllSessionsBothSides() {
        // Snapshot the soon-to-be-orphaned location entries before we
        // wipe events. Anything bound to a session we're about to
        // delete is dropped; the active session's pin (if any) is
        // preserved alongside its protected event ids.
        let protected = protectedEventIDs()
        let doomedLocationIDs: Set<UUID> = Set(
            deviceSessions
                .map { $0.id }
                .filter { !protected.contains($0) }
        )

        motionLogManager.clearAllEvents(for: deviceID, protecting: protected)
        locationStore.forget(sessionIDs: doomedLocationIDs)
        SessionNameStore.shared.forget(sessionIDs: doomedLocationIDs)
        if bluetoothManager.connectedDevice != nil {
            bluetoothManager.clearMotionLog()
        }
    }

    /// Sessions on a specific day for this device, oldest-first.
    /// Inline replacement for the old MotionSessionsRepository helper —
    /// reads the same parser output that the rest of the view uses.
    private func sessionsOn(_ day: Date) -> [MotionSession] {
        let cal = Calendar.current
        return deviceSessions.filter { session in
            guard let start = session.startedAt else { return false }
            return cal.isDate(start, inSameDayAs: day)
        }
        .sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    /// Sunday-first calendar — the user asked for "A week is Sunday –
    /// Saturday" explicitly. Don't trust the device locale's
    /// `firstWeekday` (which is Sunday in en_US but Monday in much of
    /// the world).
    private static var sundayFirstCalendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }()

    private func dayClearLabel(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Clear today's sessions" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Clear sessions on \(f.string(from: day))"
    }

    private func weekClearLabel(for day: Date) -> String {
        let cal = Self.sundayFirstCalendar
        if cal.isDate(Date(), equalTo: day, toGranularity: .weekOfYear) {
            return "Clear this week's sessions"
        }
        let weekStart = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Clear week of \(f.string(from: weekStart))"
    }

    private func monthClearLabel(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(Date(), equalTo: day, toGranularity: .month) {
            return "Clear this month's sessions"
        }
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return "Clear sessions for \(f.string(from: day))"
    }

    private func clearForDay(_ day: Date) {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .day, for: day) else { return }
        clearEvents(in: interval.start ..< interval.end)
    }

    private func clearForWeek(containing day: Date) {
        let cal = Self.sundayFirstCalendar
        guard let interval = cal.dateInterval(of: .weekOfYear, for: day) else { return }
        clearEvents(in: interval.start ..< interval.end)
    }

    private func clearForMonth(containing day: Date) {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: day) else { return }
        clearEvents(in: interval.start ..< interval.end)
    }

    /// Shared body for the partial-range clear menu items. Drops the
    /// matching events from MotionLogManager and the corresponding
    /// location pins from SessionLocationStore in lockstep, both
    /// honouring the active-session protection set so an in-progress
    /// lock survives every clear.
    private func clearEvents(in range: Range<Date>) {
        let protected = protectedEventIDs()
        let doomedLocationIDs: Set<UUID> = Set(
            deviceSessions
                .filter { session in
                    guard !protected.contains(session.id) else { return false }
                    guard let start = session.startedAt else { return false }
                    return range.contains(start)
                }
                .map { $0.id }
        )

        motionLogManager.clearEventsInRange(range,
                                            deviceID: deviceID,
                                            protecting: protected)
        locationStore.forget(sessionIDs: doomedLocationIDs)
        SessionNameStore.shared.forget(sessionIDs: doomedLocationIDs)
    }

    // MARK: - Lifecycle hooks

    /// Called from the view's onAppear. Does all the work that used to
    /// live on the BLE / event hot path:
    ///   - Asks for location permission (idempotent — system shows the
    ///     dialog at most once).
    ///   - Sweeps any SESSION_START events that haven't yet been bound
    ///     to a location and tries to associate them with whatever
    ///     pending capture lives in SessionLocationStore.
    ///   - Starts the motion-log polling timer so the feed and event
    ///     log stay live while the user is on this screen — same
    ///     behaviour the deleted MotionLogsView used to have.
    private func onMotionReportAppeared() {
        locationStore.requestAuthorizationIfNeeded()

        for event in motionLogManager.motionEvents
            where event.eventType == .sessionStart
            && event.deviceID == deviceID
            && locationStore.location(for: event.id) == nil {
            locationStore.associateIfPending(eventID: event.id,
                                             eventTimestamp: event.timestamp)
        }

        bluetoothManager.startMotionLogPolling()
    }

    private func onMotionReportDisappeared() {
        bluetoothManager.stopMotionLogPolling()
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let text: String
    var body: some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(0.4)
            Spacer()
        }
    }
}

/// "Show N more" row that replaces hidden session cards in a feed day
/// section when the day has more than 2 sessions. Styled as a compact
/// link-style row centred under the visible cards.
private struct FeedExpandRow: View {
    let hiddenCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.callout)
                    .fontWeight(.semibold)
                Text("Show \(hiddenCount) more")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status badge

struct SessionStatusBadge: View {
    let status: SessionStatus
    var body: some View {
        Text(status.label.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .tracking(0.4)
            .foregroundColor(status.badgeForeground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(status.badgeBackground)
            )
    }
}

// MARK: - Active session card

private struct ActiveSessionCard: View {
    let session: MotionSession
    let deviceID: UUID
    @State private var liveNow: Date = Date()
    /// Tick once a second so the duration counter advances live. Keep
    /// state-local so other cards don't redraw on this timer.
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationLink {
            SessionDetailView(session: session)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SessionStatus.active.badgeForeground)
                            .frame(width: 8, height: 8)
                        Text("ACTIVE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .tracking(0.4)
                            .foregroundColor(SessionStatus.active.badgeForeground)
                    }
                    Spacer()
                    Text(session.shortDurationString(now: liveNow))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Text(locationPlaceholder)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(activeSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                SessionSparkline(session: session)
                    .frame(height: 18)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        // Pulse is implemented via phaseAnimator on the
                        // stroke itself, not via withAnimation +
                        // repeatForever on a shared @State. The previous
                        // approach created an ambient animation
                        // transaction that ALSO captured concurrent
                        // state changes happening in the view tree
                        // (live duration tick, log-drain updating
                        // MotionLogManager) — which is why the whole
                        // report screen was visibly drifting up and
                        // down every 1.5s. phaseAnimator scopes the
                        // animation to just this overlay's opacity, so
                        // no layout-affecting properties are touched.
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SessionStatus.active.badgeForeground, lineWidth: 3)
                            .phaseAnimator([false, true]) { content, isBright in
                                content.opacity(isBright ? 1.0 : 0.45)
                            } animation: { _ in
                                .easeInOut(duration: 1.5)
                            }
                    )
            )
        }
        .buttonStyle(.plain)
        .onReceive(timer) { liveNow = $0 }
    }

    private var locationPlaceholder: String { "WatchDog session" }

    private var activeSubtitle: String {
        let count = session.events.count
        if let start = session.startedAt {
            let f = DateFormatter()
            f.timeStyle = .short
            return "Locked \(f.string(from: start)) · \(count) motion event\(count == 1 ? "" : "s")"
        } else {
            return "\(count) motion event\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Session card

struct SessionCard: View {
    let session: MotionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SessionStatusBadge(status: session.status)
                Spacer()
                Text(session.shortDurationString())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Text(locationPlaceholder)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(timeRangeText)
                .font(.caption)
                .foregroundColor(.secondary)
            SessionSparkline(session: session)
                .frame(height: 16)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.8), lineWidth: 1.2)
                )
        )
    }

    private var locationPlaceholder: String { "WatchDog session" }

    private var timeRangeText: String {
        let f = DateFormatter()
        f.timeStyle = .short

        switch (session.startedAt, session.endedAt) {
        case let (start?, end?):
            var s = "\(f.string(from: start)) – \(f.string(from: end))"
            if session.status == .alarmed, let fired = session.alarmFiredAt {
                s += " · alarm at \(f.string(from: fired))"
            }
            return s
        case let (start?, nil):
            return "Started \(f.string(from: start)) · end not confirmed"
        case (nil, _):
            return "Unknown start time"
        }
    }
}

// MARK: - Sparkline

/// Tiny inline preview of motion intensity over the session duration.
/// "Intensity" is synthesized from event density — the firmware doesn't
/// stream continuous accelerometer data, so this is best-effort but reads
/// intuitively. A flat line = peaceful; a spike = motion fired.
private struct SessionSparkline: View {
    let session: MotionSession

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let h = geo.size.height
                let w = geo.size.width
                Path { path in
                    let baseline = h - 2
                    path.move(to: CGPoint(x: 0, y: baseline))
                    for point in samplePoints(width: w, baseline: baseline) {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: w, y: baseline))
                }
                .stroke(session.status.accentColor, lineWidth: 1.2)
            }
        }
    }

    private func samplePoints(width: CGFloat, baseline: CGFloat) -> [CGPoint] {
        guard let start = session.startedAt, let end = session.endedAt,
              end > start, !session.events.isEmpty else {
            return [CGPoint(x: width, y: baseline)]
        }
        let total = end.timeIntervalSince(start)
        return session.events.compactMap { event -> CGPoint? in
            guard let ts = event.timestamp else { return nil }
            let frac = max(0, min(1, ts.timeIntervalSince(start) / total))
            let x = CGFloat(frac) * width
            let intensity = event.alarmSounded ? 1.0 : 0.55
            let y = baseline - CGFloat(intensity) * (baseline - 2)
            return CGPoint(x: x, y: y)
        }
        .flatMap { spike in [
            CGPoint(x: spike.x - 1, y: baseline),
            spike,
            CGPoint(x: spike.x + 1, y: baseline)
        ] }
    }
}

// MARK: - Calendar month grid

private struct CalendarMonthGrid: View {
    @Binding var selectedDate: Date
    let dotsByDay: [Date: SessionStatus]
    var onMonthLabelTap: (() -> Void)? = nil

    @State private var currentMonth: Date = Date()
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.title3)
                }
                Spacer()
                Button { onMonthLabelTap?() } label: {
                    HStack(spacing: 4) {
                        Text(monthLabel)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.title3)
                }
            }
            .padding(.horizontal, 4)
            // Extra breathing room between the month/year title and the
            // weekday row below — the previous tight stack made the
            // dates look like they were stuck to "June 2026".
            .padding(.bottom, 10)

            HStack(spacing: 0) {
                ForEach(cal.veryShortWeekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date {
                        DayCell(
                            date: date,
                            isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                            isToday: cal.isDateInToday(date),
                            statusDot: dotsByDay[cal.startOfDay(for: date)]
                        ) {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                selectedDate = date
                            }
                        }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            if cal.dateInterval(of: .month, for: newDate)?.start
                != cal.dateInterval(of: .month, for: currentMonth)?.start {
                currentMonth = newDate
            }
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: currentMonth)
    }

    private func shiftMonth(_ delta: Int) {
        if let new = cal.date(byAdding: .month, value: delta, to: currentMonth) {
            currentMonth = new
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: currentMonth) else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        var d = interval.start
        while d < interval.end {
            days.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return days
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let statusDot: SessionStatus?
    let onTap: () -> Void

    private let cal = Calendar.current

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .foregroundColor(textColor)
                Circle()
                    .fill(statusDot?.badgeForeground ?? .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isToday && !isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
            )
            // Make the entire cell area hit-testable, including the
            // transparent regions inside the rounded background. Without
            // this, SwiftUI only registers taps on the painted content
            // (the day number + dot), which is why the previous build
            // dropped taps on the edges.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        isSelected ? .white : .primary
    }
}

// MARK: - Sliding segmented control

/// Tap or drag to change selection. Same visual language as the
/// `AnimatedSegmentedControl` used for the sensitivity setting (filled
/// blue pill slides under the active label, light haptic on change), with
/// one important difference: a `DragGesture(minimumDistance: 0)` makes the
/// whole control drag-responsive, so swiping across the segments moves
/// the selection in real time. iOS's own `.pickerStyle(.segmented)` is
/// tap-only and was being flaky about which tap registered, which is
/// what produced the "multiple taps needed" report.
struct SlidingSegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    @State private var lastHapticIndex: Int? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let segWidth = options.isEmpty ? 0 : geo.size.width / CGFloat(options.count)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .frame(width: max(0, segWidth))
                    .offset(x: CGFloat(selectedIndex) * segWidth)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selection)

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Text(label(option))
                            .font(.subheadline)
                            .fontWeight(selection == option ? .semibold : .regular)
                            .foregroundColor(selection == option ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                }
            }
            .contentShape(Rectangle())
            // Single drag gesture handles BOTH tap and drag — minimum
            // distance 0 makes the initial touch immediately register as
            // a drag, and subsequent finger movement updates selection
            // as it crosses segment boundaries.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !options.isEmpty, segWidth > 0 else { return }
                        let raw = Int(value.location.x / segWidth)
                        let idx = max(0, min(options.count - 1, raw))
                        let newOption = options[idx]
                        if newOption != selection {
                            if lastHapticIndex != idx {
                                haptic.impactOccurred()
                                lastHapticIndex = idx
                            }
                            selection = newOption
                        }
                    }
                    .onEnded { _ in
                        lastHapticIndex = nil
                    }
            )
        }
        .frame(height: 36)
    }

    private var selectedIndex: Int {
        options.firstIndex(of: selection) ?? 0
    }
}

// MARK: - Month/year picker

/// Modal sheet for jumping straight to any month/year that has data —
/// useful once a user accumulates more than a few weeks of sessions. Two
/// side-by-side wheel pickers; the trailing count next to each month/year
/// row is the session count for that bucket. Same UX the deleted
/// MotionLogsView had for events; carried over for sessions.
private struct MonthYearPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let sessionsByMonth: [Date: Int]

    @State private var pickerMonth: Int
    @State private var pickerYear: Int

    private let cal = Calendar.current
    private let monthSymbols = Calendar.current.monthSymbols

    private var years: [Int] {
        let thisYear = cal.component(.year, from: Date())
        let earliest = sessionsByMonth.keys
            .map { cal.component(.year, from: $0) }
            .min() ?? thisYear
        return Array(earliest...thisYear)
    }

    init(selectedDate: Binding<Date>, sessionsByMonth: [Date: Int]) {
        self._selectedDate = selectedDate
        self.sessionsByMonth = sessionsByMonth
        let c = Calendar.current
        _pickerMonth = State(initialValue: c.component(.month, from: selectedDate.wrappedValue))
        _pickerYear  = State(initialValue: c.component(.year,  from: selectedDate.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                let count = sessionCount(month: pickerMonth, year: pickerYear)
                Text(count == 0
                     ? "No sessions in \(monthSymbols[pickerMonth - 1]) \(String(pickerYear))"
                     : "\(count) session\(count == 1 ? "" : "s") in \(monthSymbols[pickerMonth - 1]) \(String(pickerYear))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                HStack(spacing: 0) {
                    Picker("Month", selection: $pickerMonth) {
                        ForEach(1...12, id: \.self) { month in
                            HStack {
                                Text(monthSymbols[month - 1])
                                let c = sessionCount(month: month, year: pickerYear)
                                if c > 0 {
                                    Text("(\(c))").foregroundColor(.secondary)
                                }
                            }
                            .tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Year", selection: $pickerYear) {
                        ForEach(years, id: \.self) { year in
                            HStack {
                                Text(String(year))
                                let c = sessionCount(year: year)
                                if c > 0 {
                                    Text("(\(c))").foregroundColor(.secondary)
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
            .navigationTitle("Jump to month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Go") {
                        apply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func sessionCount(month: Int, year: Int) -> Int {
        var c = DateComponents(); c.year = year; c.month = month
        if let start = cal.date(from: c) { return sessionsByMonth[start] ?? 0 }
        return 0
    }

    private func sessionCount(year: Int) -> Int {
        (1...12).reduce(0) { $0 + sessionCount(month: $1, year: year) }
    }

    /// Land on day 1 of the chosen month, unless it's the current month —
    /// then jump to today so the calendar dot still highlights correctly.
    private func apply() {
        let now = Date()
        if pickerMonth == cal.component(.month, from: now)
            && pickerYear == cal.component(.year, from: now) {
            selectedDate = now
            return
        }
        var c = DateComponents()
        c.year = pickerYear; c.month = pickerMonth; c.day = 1
        if let d = cal.date(from: c) { selectedDate = d }
    }
}

#Preview {
    NavigationStack {
        MotionReportView(bluetoothManager: BluetoothManager(), deviceID: UUID())
    }
}
