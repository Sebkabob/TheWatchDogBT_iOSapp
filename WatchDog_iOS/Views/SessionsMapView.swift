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

struct SessionMapPin: Identifiable, Hashable {
    let session: MotionSession
    let location: SessionLocation
    var id: UUID { session.id }
}

struct SessionsMapView: View {
    let pins: [SessionMapPin]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasFramedInitial = false

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(pins) { pin in
                Annotation(annotationTitle(for: pin),
                           coordinate: pin.location.coordinate) {
                    NavigationLink {
                        SessionDetailView(session: pin.session)
                    } label: {
                        SessionMapPinView(status: pin.session.status)
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
            // One-shot initial framing. Computing a tight region across
            // pins and a tiny default-region fallback for the single-pin
            // case so the map opens at the right zoom level.
            guard !hasFramedInitial else { return }
            hasFramedInitial = true
            if let rect = enclosingRect() {
                cameraPosition = .rect(rect)
            }
        }
    }

    private func annotationTitle(for pin: SessionMapPin) -> String {
        pin.session.status.label
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
        // 25% padding on each side via inset with negative dx/dy.
        let dx = rawRect.size.width  * 0.25
        let dy = rawRect.size.height * 0.25
        return rawRect.insetBy(dx: -dx, dy: -dy)
    }
}

/// The visible pin glyph. Bigger filled circle in the status color, white
/// ring around it for contrast against satellite / dark map styles.
private struct SessionMapPinView: View {
    let status: SessionStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(status.badgeForeground)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
            // Inner dot — visual weight that survives any tinting iOS
            // may apply during selection animations.
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
    }
}

#Preview {
    NavigationStack {
        SessionsMapView(pins: [])
    }
}
