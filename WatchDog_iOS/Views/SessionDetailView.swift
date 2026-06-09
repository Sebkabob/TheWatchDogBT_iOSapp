//
//  SessionDetailView.swift
//  WatchDog_iOS
//
//  Created by Sebastian Forenza 2026.
//
//  The story view for a single MotionSession. Pushed from the feed or the
//  calendar tab in MotionReportView; same screen regardless of how the user
//  got here.
//
//  Layout (top → bottom):
//    1. Status banner — color-coded by session.status, headlines the verdict
//       and the time range. For .alarmed sessions this is the eye-catcher.
//    2. Map thumbnail placeholder — location capture isn't implemented yet,
//       so this slot shows an empty state explaining that. Will become a
//       real MapKit snapshot when CoreLocation lands.
//    3. Motion timeline — horizontal chart from SESSION_START to
//       SESSION_END (or to "now" for active sessions). Above the axis:
//       intensity area chart synthesized from event density. Below: one
//       dot per discrete event, color-coded by type.
//    4. Event log — plain-English list of every event in the session,
//       including the SESSION_START and SESSION_END themselves as
//       "Session start · locked" / "Session end · unlocked" bookends.
//

import SwiftUI
import MapKit

struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let session: MotionSession

    /// Live-tick for active sessions so the duration counter and the
    /// right edge of the timeline advance in real time.
    @State private var liveNow: Date = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    /// User-editable session name. Initialised from SessionNameStore in
    /// `onAppear` so the field reflects any previously-set name, then
    /// kept in sync on every change.
    @State private var sessionName: String = ""

    /// Reverse-geocoded street-level description of the lock location.
    /// Filled in asynchronously by CLGeocoder when the view appears.
    /// nil while loading or when the session has no location at all;
    /// the UI shows the address-row only when a value is available.
    @State private var addressLine: String? = nil
    @State private var showDeleteConfirmation = false
    private static let geocoder = CLGeocoder()

    private let maxNameLength = 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sessionNameField
                    .padding(.horizontal, 16)

                statusBanner
                    .padding(.horizontal, 16)

                if let addressLine, !addressLine.isEmpty {
                    Text("Near \(addressLine)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                }

                mapThumbnail
                    .padding(.horizontal, 16)

                Section {
                    SessionTimelineChart(session: session, now: liveNow)
                        .frame(height: 120)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.separator).opacity(0.8), lineWidth: 1.2)
                                )
                        )
                        .padding(.horizontal, 16)
                } header: {
                    sectionLabel("MOTION TIMELINE")
                }

                Section {
                    eventLog
                        .padding(.horizontal, 16)
                } header: {
                    sectionLabel("EVENT LOG")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Sessions")
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Session")
                    .font(.headline)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete this session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteThisSession() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This wipes the session's events, its pin, and any name you've set. Cannot be undone.")
        }
        .onReceive(timer) { liveNow = $0 }
        .onAppear {
            sessionName = SessionNameStore.shared.name(for: session.id) ?? ""
            startReverseGeocode()
        }
    }

    private func deleteThisSession() {
        MotionLogManager.shared.remove(sessions: [session])
        SessionLocationStore.shared.forget(sessionIDs: [session.id])
        SessionNameStore.shared.forget(sessionIDs: [session.id])
        // Pop back to whatever pushed us — feed, calendar, or cluster
        // detail. The parent's body recomputes deviceSessions from
        // MotionLogManager.motionEvents on its next render and the
        // now-deleted session simply won't be in the list.
        dismiss()
    }

    // MARK: - Session name

    /// Editable name field, same visual style as the device-name field
    /// in DevicePageView's settings panel. Empty by default; the user
    /// can type a label like "Office desk" or "Bike at Blue Bottle" and
    /// it persists to UserDefaults via SessionNameStore.
    private var sessionNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session name")
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField("Name this session", text: $sessionName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .cornerRadius(10)
                .submitLabel(.done)
                .autocorrectionDisabled(true)
                .onChange(of: sessionName) { _, newValue in
                    // Enforce the same length cap WatchDog names use.
                    let limited = String(newValue.prefix(maxNameLength))
                    if limited != newValue { sessionName = limited }
                    SessionNameStore.shared.setName(limited, for: session.id)
                }
        }
    }

    // MARK: - Banner

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.status.label.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.4)
                Spacer()
                // Self-driving duration counter — TimelineView re-runs
                // its closure every second so an active session's
                // elapsed time advances live, regardless of whether
                // any other state in the view is changing.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(session.shortDurationString(now: context.date))
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            Text(headlineText)
                .font(.headline)
                .padding(.top, 1)
            Text(subtitleText)
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundColor(session.status.badgeForeground)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(session.status.badgeBackground)
        )
    }

    // (durationString helper removed — the banner now renders its own
    // duration via TimelineView so this property had no callers.)

    private var headlineText: String {
        switch session.status {
        case .alarmed:        return alarmedHeadline
        case .disturbed:      return "Motion detected"
        case .peaceful:       return "Nothing happened"
        case .active:         return "Session in progress"
        case .activeOffline:  return "Session in progress (device offline)"
        case .incomplete:     return "Session ended uncleanly"
        }
    }

    /// Headline for a session that fired the alarm. Picks the tone from
    /// the first alarmed event in the session (a session typically has
    /// one tone; if it has more — the user changed AlarmType mid-session —
    /// the first one is shown). Legacy alarmed events with no
    /// firedAlarmType fall back to the generic phrasing.
    private var alarmedHeadline: String {
        let firstAlarmedTone = session.events.first(where: { $0.alarmSounded })?.firedAlarmType
        if let tone = firstAlarmedTone, !tone.firedLabel.isEmpty {
            return "\(tone.firedLabel) alarm fired during this session"
        }
        return "Alarm fired during this session"
    }

    private var subtitleText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let dayF = DateFormatter()
        dayF.dateStyle = .medium
        let timeF = DateFormatter()
        timeF.timeStyle = .short

        switch (session.startedAt, session.endedAt) {
        case let (start?, end?):
            return "\(dayF.string(from: start)) · \(timeF.string(from: start)) – \(timeF.string(from: end))"
        case let (start?, nil):
            return "\(dayF.string(from: start)) · started \(timeF.string(from: start))"
        case (nil, _):
            return "Unknown start time"
        }
    }

    // MARK: - Map snapshot

    /// Small static map showing the lock location with a status-colored
    /// pin. Falls back to an empty state when the session didn't get a
    /// location captured (older sessions, location permission denied,
    /// no GPS fix at lock time). Non-interactive — the Map tab is the
    /// place for panning/zooming.
    @ViewBuilder
    private var mapThumbnail: some View {
        if let location = SessionLocationStore.shared.location(for: session.id) {
            Button {
                openInAppleMaps(location: location)
            } label: {
                DetailMap(location: location, status: session.status)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.8), lineWidth: 1.2)
                    )
                    // Tap glyph in the corner so it's discoverable that
                    // the map is interactive. The Map view itself has
                    // interactionModes = [] so it doesn't catch the tap.
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.forward.square.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "mappin.slash")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("Location not captured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Older sessions and sessions locked without location permission don't have a pin.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(0.7)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.8), lineWidth: 1.2)
                    )
            )
        }
    }

    // MARK: - Map interaction helpers

    /// Launches Apple Maps centred on the lock coordinate with a pin.
    /// Uses the captured session name (if any) as the pin title so the
    /// destination card reads "Office desk" / "Bike at Blue Bottle"
    /// rather than the raw coordinate.
    private func openInAppleMaps(location: SessionLocation) {
        let coordinate = location.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        let trimmed = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        mapItem.name = trimmed.isEmpty ? "WatchDog session" : trimmed
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapTypeKey: MKMapType.standard.rawValue
        ])
    }

    /// Reverse-geocode the lock coordinate into a short human-readable
    /// line ("Near 1234 State St") that renders above the map. CLGeocoder
    /// is rate-limited and asynchronous; we cache nothing here because
    /// reverse-geocoding once per detail-view appearance is well below
    /// the daily quota, but we do bail silently on any error.
    private func startReverseGeocode() {
        guard let location = SessionLocationStore.shared.location(for: session.id) else {
            addressLine = nil
            return
        }
        let cl = CLLocation(latitude: location.lat, longitude: location.lng)
        Self.geocoder.reverseGeocodeLocation(cl) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            // Prefer "subThoroughfare thoroughfare" (e.g. "1234 State
            // St"); fall back to thoroughfare alone, then name, then
            // locality so we always have something useful to show.
            let pieces = [placemark.subThoroughfare, placemark.thoroughfare]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let line: String?
            if !pieces.isEmpty {
                line = pieces.joined(separator: " ")
            } else if let name = placemark.name, !name.isEmpty {
                line = name
            } else {
                line = placemark.locality
            }
            DispatchQueue.main.async {
                self.addressLine = line
            }
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.5)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Event log

    private var eventLog: some View {
        // Reference day = the day the session started. Event-log rows
        // whose timestamps fall on a different day prepend the date
        // (e.g. "1/1 3:42:15 PM") so a session that spans midnight is
        // legible. Rows on the same day show just the time.
        let referenceDay = session.startedAt

        return VStack(spacing: 0) {
            EventLogRow(time: session.startedAt,
                        referenceDay: referenceDay,
                        label: "Session start · locked",
                        emphasised: false)
            ForEach(Array(session.events.enumerated()), id: \.offset) { _, event in
                Divider()
                // Compose label: "Type [· 1.2s] [· Loud alarm fired]". The
                // duration segment is only shown when the firmware reports
                // a meaningful value (>1 tick — a 1-tick event is the
                // instantaneous floor and tells the user nothing). Legacy
                // events recorded before the duration byte shipped have a
                // nil ticks field and naturally fall through to the
                // single-segment label. The alarm-fired segment carries the
                // tone (Loud/Normal/Calm) that was active at processing
                // time; legacy alarmed events with no firedAlarmType fall
                // back to the generic "alarm fired" string.
                let durSegment = MotionEventLabel.durationSuffix(forTicks: event.durationTicks250ms)
                let alarmSegment: String = {
                    guard event.alarmSounded else { return "" }
                    if let tone = event.firedAlarmType, !tone.firedLabel.isEmpty {
                        return " · \(tone.firedLabel) alarm fired"
                    }
                    return " · alarm fired"
                }()
                let label = "\(event.eventType.displayName)\(durSegment)\(alarmSegment)"
                EventLogRow(time: event.timestamp,
                            referenceDay: referenceDay,
                            label: label,
                            emphasised: event.alarmSounded)
            }
            if session.endedAt != nil {
                Divider()
                EventLogRow(time: session.endedAt,
                            referenceDay: referenceDay,
                            label: "Session end · unlocked",
                            emphasised: false)
            } else if session.status == .incomplete {
                Divider()
                EventLogRow(time: nil,
                            referenceDay: referenceDay,
                            label: "No SESSION_END marker received",
                            emphasised: true,
                            tint: SessionStatus.incomplete.badgeForeground)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.8), lineWidth: 1.2)
                )
        )
    }
}

/// Formatting helpers shared by the event log + (future) any other surface
/// that wants to render a motion event's duration in human terms.
enum MotionEventLabel {
    /// Format the firmware's 250 ms-tick duration field for inline use in
    /// event-log labels. Returns either " · <value>" or "" — the leading
    /// " · " is part of the suffix so callers can interpolate it directly
    /// after the event-type name without juggling separators.
    ///
    /// Rules:
    /// - nil ticks (legacy event recorded before the firmware shipped the
    ///   duration byte) → "".
    /// - 1 tick is the instantaneous floor — FSM impact/freefall, MLC
    ///   blips that never reached deferred-settle. Showing "0.3s" there
    ///   misleads, since it just means "no real measurement available."
    ///   Suppress.
    /// - <10s: one decimal place ("2.5s"), feels natural for door-handling
    ///   and the like.
    /// - ≥10s: integer seconds ("12s"), avoids spurious precision on
    ///   long events that are usually rounded anyway.
    /// - 255 ticks is the saturation sentinel (~63.75s) — denote with "+"
    ///   so a graph reader can tell the field maxed out.
    static func durationSuffix(forTicks ticks: UInt8?) -> String {
        guard let ticks, ticks > 1 else { return "" }
        let seconds = Double(ticks) * 0.25
        let saturated = (ticks == 255)
        let body: String
        if seconds < 10 {
            body = String(format: "%.1fs", seconds)
        } else {
            body = String(format: "%.0fs", seconds)
        }
        return " · \(body)\(saturated ? "+" : "")"
    }
}

private struct EventLogRow: View {
    let time: Date?
    /// Used to decide whether to prepend the date. Typically the
    /// session's start date — same-day events show time only, cross-day
    /// events get "M/d h:mm:ss a".
    let referenceDay: Date?
    let label: String
    let emphasised: Bool
    var tint: Color? = nil

    private var timeString: String {
        guard let t = time else { return "—" }
        let cal = Calendar.current
        let f = DateFormatter()
        if let ref = referenceDay, !cal.isDate(t, inSameDayAs: ref) {
            // Mixed-day session — show date prefix so a row at 1:00 AM
            // the next day doesn't look like it happened first.
            f.dateFormat = "M/d h:mm:ss a"
        } else {
            // Same-day rows: time only, but include seconds so two
            // events fired within the same minute are distinguishable.
            f.dateFormat = "h:mm:ss a"
        }
        return f.string(from: t)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(timeString)
                .font(.callout)
                .monospacedDigit()
                .foregroundColor(tint ?? (emphasised ? .red : .secondary))
                // Wider min-width to accommodate the optional date
                // prefix without truncating "12:34:56 PM" on the
                // common path.
                .frame(minWidth: 100, alignment: .leading)
            Text(label)
                .font(.callout)
                .foregroundColor(tint ?? (emphasised ? .red : .primary))
                .fontWeight(emphasised ? .semibold : .regular)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Timeline chart

/// Horizontal area-chart from session start to session end. Intensity
/// (y-axis) is synthesized from event density — the firmware only logs
/// discrete events, not continuous accelerometer, so we render a 1-second
/// bump per event scaled by severity. Reads intuitively without
/// promising precision we don't have.
struct SessionTimelineChart: View {
    let session: MotionSession
    let now: Date

    var body: some View {
        // VStack splits the chart area (top) from the time labels (bottom)
        // so events landing near the start or end of the timeline can't
        // overlap with the time text. The chart's GeometryReader claims
        // all available vertical space minus the fixed label row at the
        // bottom.
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let axisY = h - 10
                let dotsY = h - 3

                ZStack(alignment: .topLeading) {
                    // Per-alarm-event narrow bands rather than one big
                    // shaded rectangle spanning the alarm window. The old
                    // rectangle extended from first alarm event to
                    // last + 20 s, which on a multi-hour session with
                    // alarms bookending it filled almost the entire chart
                    // and looked like "everything is highlighted." A
                    // narrow band per event reads correctly as "this is
                    // when the alarm fired."
                    ForEach(Array(alarmBands(width: w, height: axisY).enumerated()), id: \.offset) { _, band in
                        Rectangle()
                            .fill(SessionStatus.alarmed.badgeBackground)
                            .frame(width: band.width, height: band.height)
                            .position(x: band.midX, y: band.midY)
                    }

                    Path { path in
                        path.move(to: CGPoint(x: 0, y: axisY))
                        path.addLine(to: CGPoint(x: w, y: axisY))
                    }
                    .stroke(Color(.separator), lineWidth: 0.5)

                    Path { path in
                        path.move(to: CGPoint(x: 0, y: axisY))
                        for pt in intensityPath(width: w, axisY: axisY) {
                            path.addLine(to: pt)
                        }
                        path.addLine(to: CGPoint(x: w, y: axisY))
                        path.closeSubpath()
                    }
                    .fill(session.status.accentColor.opacity(0.35))

                    Path { path in
                        let pts = intensityPath(width: w, axisY: axisY)
                        if let first = pts.first {
                            path.move(to: first)
                            for pt in pts.dropFirst() { path.addLine(to: pt) }
                        }
                    }
                    .stroke(session.status.accentColor, lineWidth: 1.3)

                    ForEach(Array(eventDots(width: w, axisY: dotsY).enumerated()), id: \.offset) { _, dot in
                        Circle()
                            .fill(dot.color)
                            .frame(width: 6, height: 6)
                            .position(x: dot.x, y: dot.y)
                    }
                }
            }

            // Fixed-height time-label row, well below the dots. Three
            // segments: start, optional alarm-time middle, end.
            HStack {
                Text(formatTime(session.startedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                if let mid = midLabel() {
                    Text(mid)
                        .font(.caption2)
                        .foregroundColor(SessionStatus.alarmed.badgeForeground)
                        .monospacedDigit()
                }
                Spacer()
                Text(formatTime(endReference))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .frame(height: 14)
        }
    }

    private var endReference: Date? {
        session.endedAt ?? (session.status == .active ? now : session.startedAt)
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func midLabel() -> String? {
        guard let fired = session.alarmFiredAt else { return nil }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: fired)
    }

    /// Build the area-chart polyline. Each event contributes a tiny
    /// triangular bump centered on its timestamp; baseline elsewhere.
    private func intensityPath(width: CGFloat, axisY: CGFloat) -> [CGPoint] {
        guard let start = session.startedAt else { return [CGPoint(x: 0, y: axisY), CGPoint(x: width, y: axisY)] }
        let end = endReference ?? start.addingTimeInterval(60)
        let total = max(1, end.timeIntervalSince(start))

        var pts: [CGPoint] = [CGPoint(x: 0, y: axisY)]
        for event in session.events {
            guard let ts = event.timestamp else { continue }
            let frac = max(0, min(1, ts.timeIntervalSince(start) / total))
            let x = CGFloat(frac) * width
            let amp: CGFloat = event.alarmSounded ? 0.85 : 0.5
            let peakY = axisY - amp * (axisY - 6)
            pts.append(CGPoint(x: x - 4, y: axisY))
            pts.append(CGPoint(x: x, y: peakY))
            pts.append(CGPoint(x: x + 4, y: axisY))
        }
        pts.append(CGPoint(x: width, y: axisY))
        return pts
    }

    /// Narrow vertical bands behind the chart, one per alarm-classified
    /// event. Replaces the single wide rectangle that used to span the
    /// alarm window (first alarm event → last + 20 s) — on a multi-hour
    /// session that filled nearly the whole chart and read as "everything
    /// is highlighted." Each band is centered on the event's timestamp
    /// and clamped to a minimum width so a tap-and-set-down (instantaneous
    /// event) still leaves a visible marker.
    private func alarmBands(width: CGFloat, height: CGFloat) -> [CGRect] {
        guard session.status == .alarmed,
              let start = session.startedAt,
              let end = endReference else { return [] }
        let total = max(1, end.timeIntervalSince(start))

        // Minimum pixel width per band so the marker is visible even
        // for an instantaneous event. Scales gently with chart width so
        // a wider phone gets a slightly wider band; never less than 6 pt.
        let bandWidth = max(CGFloat(6), width * 0.012)

        var bands: [CGRect] = []
        for event in session.events where event.alarmSounded {
            guard let ts = event.timestamp else { continue }
            let frac = max(0, min(1, ts.timeIntervalSince(start) / total))
            let x = CGFloat(frac) * width - bandWidth / 2
            bands.append(CGRect(x: x, y: 0, width: bandWidth, height: height))
        }
        return bands
    }

    /// Each event becomes one colored dot beneath the axis.
    private func eventDots(width: CGFloat, axisY: CGFloat) -> [(x: CGFloat, y: CGFloat, color: Color)] {
        guard let start = session.startedAt else { return [] }
        let end = endReference ?? start.addingTimeInterval(60)
        let total = max(1, end.timeIntervalSince(start))

        return session.events.compactMap { event in
            guard let ts = event.timestamp else { return nil }
            let frac = max(0, min(1, ts.timeIntervalSince(start) / total))
            let color: Color = event.alarmSounded ? .red : .secondary
            return (CGFloat(frac) * width, axisY, color)
        }
    }
}

// MARK: - Detail map

/// Tight map centered on the lock location. Non-interactive (no
/// gestures), single annotation in the session's status color. Camera
/// region is fixed at ~600m square so the pin and surrounding streets
/// are visible without dropping into building detail.
private struct DetailMap: View {
    let location: SessionLocation
    let status: SessionStatus

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )),
            interactionModes: []) {
            Annotation("", coordinate: location.coordinate) {
                ZStack {
                    Circle()
                        .fill(status.badgeForeground)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                }
                .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: MotionSession(
            id: UUID(),
            endEventID: nil,
            deviceID: UUID(),
            startedAt: Date().addingTimeInterval(-2 * 3600),
            endedAt: Date(),
            status: .alarmed,
            events: [
                MotionEvent(deviceID: UUID(), timestamp: Date().addingTimeInterval(-90 * 60),
                            eventType: .inMotion, alarmSounded: false),
                MotionEvent(deviceID: UUID(), timestamp: Date().addingTimeInterval(-88 * 60),
                            eventType: .impact, alarmSounded: true)
            ]
        ))
    }
}
