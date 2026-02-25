//
//  Palette.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import SwiftUI

/// The visualization keeps its own dark palette rather than following the system
/// appearance: hotspot colour is data, and it has to mean the same thing in every window.
enum Palette {
    static let canvas = Color(red: 0.055, green: 0.063, blue: 0.078)
    static let panel = Color(red: 0.086, green: 0.094, blue: 0.114)
    static let hairline = Color.white.opacity(0.08)
    static let groupFill = Color.white.opacity(0.028)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.52)
    static let faintText = Color.white.opacity(0.34)
    static let accent = Color(red: 0.98, green: 0.62, blue: 0.24)
    /// Deliberately outside the heat ramp: coupling is a different kind of fact from
    /// temperature, and must not read as "slightly hotter".
    static let coupling = Color(red: 0.45, green: 0.78, blue: 0.98)

    /// Cool for quiet code, hot for code that is both complex and frequently changed.
    /// Stops are interpolated pairwise so the ramp never drifts through a muddy midpoint
    /// the way a straight blue-to-amber blend would.
    private static let ramp: [(stop: Double, color: (r: Double, g: Double, b: Double))] = [
        (0.00, (0.192, 0.220, 0.278)),
        (0.30, (0.204, 0.400, 0.522)),
        (0.55, (0.820, 0.663, 0.302)),
        (0.78, (0.882, 0.427, 0.196)),
        (1.00, (0.855, 0.196, 0.278)),
    ]

    static func hotspot(_ score: Double) -> Color {
        let value = min(max(score, 0), 1)
        for (lower, upper) in zip(ramp, ramp.dropFirst()) where value <= upper.stop {
            let span = upper.stop - lower.stop
            let t = span > 0 ? (value - lower.stop) / span : 0
            return Color(
                red: lower.color.r + (upper.color.r - lower.color.r) * t,
                green: lower.color.g + (upper.color.g - lower.color.g) * t,
                blue: lower.color.b + (upper.color.b - lower.color.b) * t
            )
        }
        let last = ramp[ramp.count - 1].color
        return Color(red: last.r, green: last.g, blue: last.b)
    }
}

extension View {
    /// Panel chrome: a flat surface with a hairline edge, used for the inspector and the
    /// timeline so they read as instruments around the canvas rather than more canvas.
    func panelBackground() -> some View {
        background(Palette.panel)
    }
}
