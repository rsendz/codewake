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

    /// Ownership colour is identity, not magnitude, so it shares nothing with the heat
    /// ramp. How many hues exist depends on how many people are in the repository: a fixed
    /// list handed a three-person team three adjacent colours out of seven, and dropped
    /// everyone past the seventh on a large team into one indistinguishable grey.
    ///
    /// Hues are spread evenly around the wheel for exactly the number of slots asked for,
    /// and consecutive slots alternate in saturation and brightness as well, so neighbours
    /// differ in more than one dimension and stay apart even when the wheel gets crowded.
    static let maximumAuthorSlots = 10

    /// How many people get a colour of their own, given how many there are.
    static func authorSlotCount(forAuthors count: Int) -> Int {
        min(max(count, 1), maximumAuthorSlots)
    }

    private static let baseHue = 0.58

    private static func authorRGB(slot: Int, of total: Int) -> (r: Double, g: Double, b: Double) {
        let total = max(total, 1)
        let hue = (baseHue + Double(slot) / Double(total)).truncatingRemainder(dividingBy: 1)
        let isAlternate = slot % 2 == 1
        return hsb(
            hue: hue,
            saturation: isAlternate ? 0.72 : 0.55,
            brightness: isAlternate ? 0.78 : 0.90
        )
    }

    static let otherAuthors = (r: 0.42, g: 0.44, b: 0.50)
    /// What a tile fades toward when no one author dominates it.
    private static let noClearOwner = (r: 0.23, g: 0.25, b: 0.30)

    /// `slot` nil means an author outside the legend. `strength` fades the colour toward
    /// neutral as ownership gets more diffuse, so a file split evenly between four people
    /// reads as belonging to nobody in particular — which is the honest answer.
    static func author(_ slot: Int?, of total: Int = maximumAuthorSlots, strength: Double = 1) -> Color {
        let base = slot.map { authorRGB(slot: $0, of: total) } ?? otherAuthors
        let t = min(max(strength, 0), 1)
        return Color(
            red: noClearOwner.r + (base.r - noClearOwner.r) * t,
            green: noClearOwner.g + (base.g - noClearOwner.g) * t,
            blue: noClearOwner.b + (base.b - noClearOwner.b) * t
        )
    }

    /// HSB to RGB. Done by hand rather than with `Color(hue:saturation:brightness:)` because
    /// author colours are interpolated toward neutral in RGB, and SwiftUI will not hand the
    /// components back.
    private static func hsb(hue: Double, saturation: Double, brightness: Double) -> (r: Double, g: Double, b: Double) {
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch index {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    /// Age is a third kind of fact again, so it gets a third scale: one hue losing its
    /// light rather than a journey across the wheel. Code that was touched today is lit;
    /// code nobody has opened since the repository started has gone out. Nothing here can
    /// be mistaken for a hotspot or for a person.
    private static let ageRamp: [(stop: Double, color: (r: Double, g: Double, b: Double))] = [
        (0.00, (0.63, 0.93, 0.87)),
        (0.22, (0.36, 0.74, 0.76)),
        (0.50, (0.23, 0.47, 0.58)),
        (0.78, (0.19, 0.27, 0.36)),
        (1.00, (0.13, 0.15, 0.19)),
    ]

    /// `share` is the file's age over the repository's own age at this point, so the scale
    /// means the same thing in a six-month-old project and a fifteen-year-old one.
    static func age(_ share: Double) -> Color {
        interpolate(ageRamp, at: share)
    }

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
        interpolate(ramp, at: score)
    }

    /// Walks a ramp of stops pairwise rather than blending end to end, so a scale never
    /// drifts through the muddy midpoint a straight two-colour interpolation would give.
    private static func interpolate(
        _ ramp: [(stop: Double, color: (r: Double, g: Double, b: Double))],
        at value: Double
    ) -> Color {
        let value = min(max(value, 0), 1)
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
