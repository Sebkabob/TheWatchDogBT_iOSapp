//
//  SessionsMapView.swift
//  WatchDog_iOS
//
//  Created by Sebastian Forenza 2026.
//
//  Map tab inside MotionReportView. Pins each session at the location
//  captured when the user locked the device. Pins are colored by session
//  status — alarmed sessions in red, peaceful in green, etc. — so the
//  map reads like a heatmap of "where did things go right or wrong."
//
//  Tap a pin → push to the session's detail screen. Same destination as
//  tapping the card in the Feed tab; one consistent way to drill in.
//
//  Camera framing: on first appearance we fit the camera to all pins
//  (or default to the user's region when there's just one). After that
//  the user can pan/zoom freely; we don't override their camera again.
//

import SwiftUI
import MapKit

struct SessionMapPin: Identifiable {
    let session: MotionSession
    let location: SessionLocation
    var id: UUID { session.id }
}

/// A group of pins that share a single map dot. Singletons are clusters
/// of size 1; the difference is purely a render decision (count badge or
/// not) and a tap behaviour (push detail vs. push the cluster list).
struct SessionCluster: Identifiable {
    /// First pin's id; stable for ForEach diffing.
    let id: UUID
    let pins: [SessionMapPin]
    /// Centroid coordinate — the visual anchor for the cluster's pin.
    let centroid: CLLocationCoordinate2D
    /// Worst status in the cluster, used for the pin colour. An alarmed
    /// session anywhere in the group makes the whole cluster red, so a
    /// busy place where something went wrong stays visually obvious.
    let status: SessionStatus

    var count: Int { pins.count }

    /// Sessions sorted newest-first — used by ClusterDetailView when the
    /// user taps a multi-session cluster.
    var sessionsNewestFirst: [MotionSession] {
        pins.map { $0.session }.sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
    }
}

struct SessionsMapView: View {
    let pins: [SessionMapPin]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasFramedInitial = false

    /// Greedy clustering radius in metres. Tighter than the typical GPS
    /// coarse-fix accuracy (10–30 m horizontalAccuracy on a phone), so
    /// genuinely different spots — opposite ends of a parking lot, two
    /// neighbouring rooms — stay as separate pins. Most "same spot"
    /// re-locks will be within a handful of metres because the user is
    /// physically standing where the device is.
    private let clusterRadiusMeters: CLLocationDistance = 30

    private var clusters: [SessionCluster] {
        Self.cluster(pins: pins, radius: clusterRadiusMeters)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(clusters) { cluster in
                Annotation(cluster.status.label,
                           coordinate: cluster.centroid) {
                    NavigationLink {
                        // Singleton → straight to detail. Multi → list
                        // view of the sessions at this location. The
                        // user shouldn't have to drill through an
                        // intermediate "1 session here" screen for the
                        // common case.
                        if cluster.count == 1, let only = cluster.pins.first {
                            SessionDetailView(session: only.session)
                        } else {
                            ClusterDetailView(cluster: cluster)
                        }
                    } label: {
                        SessionMapPinView(status: cluster.status,
                                          count: cluster.count)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            guard !hasFramedInitial else { return }
            hasFramedInitial = true
            if let rect = enclosingRect() {
                cameraPosition = .rect(rect)
            }
        }
    }

    /// MKMapRect that contains every pin, with a small padding around
    /// the edge so pins aren't flush against the viewport. Returns nil
    /// for an empty pin list.
    private func enclosingRect() -> MKMapRect? {
        guard !pins.isEmpty else { return nil }
        let points = pins.map {
            MKMapPoint(CLLocationCoordinate2D(latitude: $0.location.lat,
                                              longitude: $0.location.lng))
        }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let rawRect = MKMapRect(origin: MKMapPoint(x: minX, y: minY),
                                size: MKMapSize(width: max(maxX - minX, 1),
                                                height: max(maxY - minY, 1)))
        let dx = rawRect.size.width  * 0.25
        let dy = rawRect.size.height * 0.25
        return rawRect.insetBy(dx: -dx, dy: -dy)
    }

    // MARK: - Clustering

    /// Greedy spatial grouping. Each pin joins the first existing
    /// cluster whose seed location is within `radius` metres; otherwise
    /// it seeds a new cluster. O(n²) worst case but n is bounded by
    /// the firmware ring buffer (169 events → typical session count of
    /// a few dozen), so the cost is negligible compared with a single
    /// Map render. Order-dependent — a different input order would
    /// produce different cluster groupings near the boundary, which is
    /// fine for a visual aggregator.
    static func cluster(pins: [SessionMapPin],
                        radius: CLLocationDistance) -> [SessionCluster] {
        // Working buckets carry the raw seed coordinate so we can compute
        // the centroid at the end.
        var buckets: [(seed: CLLocation, pins: [SessionMapPin])] = []
        for pin in pins {
            let pinLoc = CLLocation(latitude: pin.location.lat,
                                    longitude: pin.location.lng)
            var attached = false
            for idx in buckets.indices {
                if buckets[idx].seed.distance(from: pinLoc) <= radius {
                    buckets[idx].pins.append(pin)
                    attached = true
                    break
                }
            }
            if !attached {
                buckets.append((seed: pinLoc, pins: [pin]))
            }
        }
        return buckets.map { bucket in
            let lats = bucket.pins.map { $0.location.lat }
            let lngs = bucket.pins.map { $0.location.lng }
            let centroid = CLLocationCoordinate2D(
                latitude:  lats.reduce(0, +) / Double(lats.count),
                longitude: lngs.reduce(0, +) / Double(lngs.count)
            )
            let status = worstStatus(in: bucket.pins)
            let id = bucket.pins.first?.id ?? UUID()
            return SessionCluster(id: id,
                                  pins: bucket.pins,
                                  centroid: centroid,
                                  status: status)
        }
    }

    /// Worst-of ordering for cluster colour. Mirrors the calendar dot
    /// rule in MotionReportView so an alarmed session in a cluster
    /// surfaces the way an alarmed day on the calendar would.
    private static func worstStatus(in pins: [SessionMapPin]) -> SessionStatus {
        let order: [SessionStatus] = [.peaceful, .disturbed, .incomplete, .active, .alarmed]
        var idx = 0
        for pin in pins {
            if let pinIdx = order.firstIndex(of: pin.session.status), pinIdx > idx {
                idx = pinIdx
            }
        }
        return order[idx]
    }
}

/// The visible pin glyph. Bigger filled circle in the status color, white
/// ring around it for contrast against satellite / dark map styles. When
/// `count > 1`, the inner dot is replaced with a count number.
private struct SessionMapPinView: View {
    let status: SessionStatus
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(status.badgeForeground)
                .frame(width: clusterSize, height: clusterSize)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))

            if count <= 1 {
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
            } else {
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
        }
        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
    }

    /// Slightly larger pin when there's a count number to fit inside.
    /// 22pt singleton → readable at any zoom; 28pt cluster gives the
    /// 2- and 3-digit counts room to breathe without crowding the
    /// surrounding map labels.
    private var clusterSize: CGFloat {
        if count >= 100 { return 32 }
        if count >= 10  { return 28 }
        if count >  1   { return 26 }
        return 22
    }
}

// MARK: - Cluster detail (tap a multi-session pin)

/// Shown when the user taps a cluster pin that bundles more than one
/// session. Groups sessions by the day they started so the user can see
/// which dates the bundled sessions occurred on (the original request:
/// "show the dates they occurred on"). Each session row pushes to the
/// regular SessionDetailView via the shared SessionCard.
struct ClusterDetailView: View {
    let cluster: SessionCluster

    /// Sessions bucketed by start-of-day, sorted newest-day-first. The
    /// inner array within each day is newest-first too, so the most
    /// recent session in the group surfaces at the top of its day.
    private var sessionsByDay: [(day: Date, sessions: [MotionSession])] {
        let cal = Calendar.current
        var buckets: [Date: [MotionSession]] = [:]
        for session in cluster.sessionsNewestFirst {
            let day: Date = session.startedAt
                .map { cal.startOfDay(for: $0) } ?? .distantPast
            buckets[day, default: []].append(session)
        }
        return buckets
            .map { ($0.key, $0.value) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(sessionsByDay.enumerated()), id: \.element.day) { _, bucket in
                    HStack {
                        Text(dayHeader(for: bucket.day))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.4)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                    ForEach(bucket.sessions) { session in
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
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(cluster.count) sessions here")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayHeader(for day: Date) -> String {
        let cal = Calendar.current
        if day == .distantPast { return "UNKNOWN DATE" }
        if cal.isDateInToday(day)     { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: day).uppercased()
    }
}

#Preview {
    NavigationStack {
        SessionsMapView(pins: [])
    }
}
