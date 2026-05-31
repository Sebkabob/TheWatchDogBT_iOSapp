//
//  View+Glass.swift
//  WatchDog_iOS
//
//  Single source of truth for the Liquid Glass adoption layer.
//
//  Apple shipped Liquid Glass in iOS 26 (WWDC 2025). Our deployment
//  target is iOS 18.5, so every glass surface has to be guarded with
//  `if #available(iOS 26.0, *)` — these helpers centralise that check
//  so call sites stay readable.
//
//  Usage rules (per Apple's "Adopting Liquid Glass"):
//    1. Glass is for the FLOATING CONTROL LAYER over content, not for
//       content cards themselves. Lock button = yes. Diagnostic card = no.
//    2. Glass can't sample other glass. Don't nest these modifiers.
//    3. Toolbar clusters that should visually merge when close: wrap them
//       in a GlassEffectContainer (also iOS-26-gated below).
//

import SwiftUI

extension View {
    /// Apply a Liquid Glass material to this view on iOS 26+; no-op on
    /// older OS versions. Use on chips, badges, floating buttons whose
    /// shape comes from `.background` / `.clipShape` rather than a
    /// SwiftUI ButtonStyle. For Button views, prefer `glassButtonStyle`.
    ///
    /// Pass `tint:` for a coloured glass variant (e.g. an arming-active
    /// chip). Pass `nil` for the default neutral regular glass.
    @ViewBuilder
    func glassControl(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint))
            } else {
                self.glassEffect()
            }
        } else {
            self
        }
    }

    /// Apply the SwiftUI `.glass` (or `.glassProminent`) button style on
    /// iOS 26+; no-op on older OS versions so the existing button style
    /// stays in effect. Use on `Button` views.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self
        }
    }

    /// Wrap a small floating informational element (battery readout, MLC
    /// state, status badge) in a glass capsule with consistent padding.
    /// On iOS 26+ the element becomes a Liquid Glass chip; on older OS
    /// versions it renders unchanged (no extra padding, no shape) so the
    /// existing layout doesn't reflow.
    @ViewBuilder
    func glassChip(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(tint))
            } else {
                self
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect()
            }
        } else {
            self
        }
    }
}

/// Wrap multiple glass elements that should share a sampling region and
/// visually merge when they're close (Apple's recommended pattern for
/// toolbars). No-op on pre-iOS-26 — children render normally.
struct GlassControlGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
    }
}
