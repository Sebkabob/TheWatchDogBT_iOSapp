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
        }
        .onReceive(timer) { liveNow = $0 }
        .onAppear {
            sessionName = SessionNameStore.shared.name(for: session.id) ?? ""
            startReverseGeocode()
        }
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
                Text(durationString)
                    .font(.caption)
                    .monospacedDigit()
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

    private var durationString: String {
        session.shortDurationString(now: liveNow)
    }

    private var headlineText: String {
        switch session.status {
        case .alarmed:    return "Alarm fired during this session"
        case .disturbed:  return "Motion detected"
        case .peaceful:   return "Nothing happened"
        case .active:     return "Session in progress"
        case .incomplete: return "Session ended uncleanly"
        }
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
                let label = "\(event.eventType.displayName)\(event.alarmSounded ? " · alarm fired" : "")"
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
                    if let alarmRect = alarmShadingRect(in: CGSize(width: w, height: axisY)) {
                        Rectangle()
                            .fill(SessionStatus.alarmed.badgeBackground)
                            .frame(width: alarmRect.width, height: alarmRect.height)
                            .position(x: alarmRect.midX, y: alarmRect.midY)
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

    /// Shaded rectangle behind the chart marking the alarm window.
    /// Heuristic: alarm fired at `alarmFiredAt`, ended either when the
    /// last alarm-classified event settled or 20 s after the first fire
    /// — firmware doesn't expose the exact LOCKED return timestamp.
    private func alarmShadingRect(in size: CGSize) -> CGRect? {
        guard session.status == .alarmed,
              let start = session.startedAt,
              let end = endReference else { return nil }
        guard let fired = session.alarmFiredAt else { return nil }
        let total = max(1, end.timeIntervalSince(start))

        let firedFrac = max(0, min(1, fired.timeIntervalSince(start) / total))
        let lastAlarmTime = session.events.last(where: { $0.alarmSounded })?.timestamp ?? fired
        let endFrac = max(firedFrac, min(1, (lastAlarmTime.timeIntervalSince(start) + 20) / total))

        let x = CGFloat(firedFrac) * size.width
        let w = max(8, CGFloat(endFrac - firedFrac) * size.width)
        return CGRect(x: x, y: 0, width: w, height: size.height)
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
