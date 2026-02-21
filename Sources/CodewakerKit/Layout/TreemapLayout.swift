//
//  TreemapLayout.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CoreGraphics
import Foundation

public struct TreemapTile: Sendable, Identifiable {
    public let hotspot: Hotspot
    public let frame: CGRect

    public var id: FileID { hotspot.id }
    public var name: String { String(hotspot.path.split(separator: "/").last ?? "") }
}

public struct TreemapGroup: Sendable, Identifiable {
    /// Top-level directory, or "/" for files at the repository root.
    public let id: String
    public let frame: CGRect
    /// Strip along the top of `frame` reserved for the group's label, empty when the group
    /// is too small to letter.
    public let headerFrame: CGRect
    public let tiles: [TreemapTile]

    public var showsHeader: Bool { !headerFrame.isEmpty }
}

/// Squarified treemap layout (Bruls, Huizing & van Wijk).
///
/// Files are sized by line count and grouped by top-level directory, so the shape of the
/// repository stays recognisable as you scrub instead of reshuffling into an unreadable
/// mosaic on every commit.
public enum TreemapLayout {
    /// Directories beyond this are folded into one "other" group; a dozen labelled regions
    /// is about the limit of what stays readable at window size.
    public static let maximumGroups = 14
    static let otherGroupName = "other"

    public static func layout(
        hotspots: [Hotspot],
        in bounds: CGRect,
        headerHeight: CGFloat = 16,
        padding: CGFloat = 2
    ) -> [TreemapGroup] {
        guard !hotspots.isEmpty, bounds.width > 1, bounds.height > 1 else { return [] }

        let groups = group(hotspots)
        let frames = squarify(groups.map(\.value), in: bounds)

        return zip(groups, frames).compactMap { group, frame in
            let padded = frame.insetBy(dx: padding, dy: padding)
            guard padded.width > 1, padded.height > 1 else { return nil }

            // Only label a group that can spare the room for a header without squeezing
            // its contents into nothing.
            let wantsHeader = padded.height > headerHeight * 3 && padded.width > 40
            let header = wantsHeader
                ? CGRect(x: padded.minX, y: padded.minY, width: padded.width, height: headerHeight)
                : .null
            let content = wantsHeader
                ? padded.divided(atDistance: headerHeight, from: .minYEdge).remainder
                : padded

            let sorted = group.hotspots.sorted { area(of: $0) > area(of: $1) }
            let tileFrames = squarify(sorted.map(area(of:)), in: content)
            let tiles = zip(sorted, tileFrames).compactMap { hotspot, tileFrame -> TreemapTile? in
                let inset = tileFrame.insetBy(dx: 0.5, dy: 0.5)
                guard inset.width > 1, inset.height > 1 else { return nil }
                return TreemapTile(hotspot: hotspot, frame: inset)
            }

            return TreemapGroup(
                id: group.name,
                frame: padded,
                headerFrame: wantsHeader ? header : .zero,
                tiles: tiles
            )
        }
    }

    /// Files are sized by length. Zero-line files (binaries, emptied files) still get a
    /// sliver so they do not silently vanish from the view.
    private static func area(of hotspot: Hotspot) -> Double {
        Double(max(hotspot.file.approximateLines, 1))
    }

    // MARK: - Grouping

    private struct Group {
        let name: String
        var hotspots: [Hotspot]
        var value: Double
    }

    private static func group(_ hotspots: [Hotspot]) -> [Group] {
        var groups: [String: Group] = [:]
        for hotspot in hotspots {
            let components = hotspot.path.split(separator: "/")
            let name = components.count > 1 ? String(components[0]) : "/"
            groups[name, default: Group(name: name, hotspots: [], value: 0)].hotspots.append(hotspot)
            groups[name]!.value += area(of: hotspot)
        }

        let sorted = groups.values.sorted { ($0.value, $1.name) > ($1.value, $0.name) }
        guard sorted.count > maximumGroups else { return sorted }

        let kept = Array(sorted.prefix(maximumGroups - 1))
        let folded = sorted.dropFirst(maximumGroups - 1)
        let other = Group(
            name: otherGroupName,
            hotspots: folded.flatMap(\.hotspots),
            value: folded.reduce(0) { $0 + $1.value }
        )
        return kept + [other]
    }

    // MARK: - Squarify

    /// Lays `values` out in `rect`, filling it completely, keeping each rectangle as close
    /// to square as the algorithm can manage. Returns one frame per value, in order.
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var frames = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return frames }

        // Work in area units scaled to the target rectangle, so a row's thickness is just
        // its area divided by the side it runs along.
        let scale = Double(rect.width) * Double(rect.height) / total
        let areas = values.map { $0 * scale }

        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0 else { break }

            // Grow the row while doing so makes its worst rectangle squarer.
            var end = start
            var rowArea = 0.0
            var bestRatio = Double.infinity
            while end < areas.count {
                let candidate = rowArea + areas[end]
                let ratio = worstAspectRatio(areas[start...end], area: candidate, side: side)
                if ratio > bestRatio { break }
                bestRatio = ratio
                rowArea = candidate
                end += 1
            }
            if end == start { end = start + 1; rowArea = areas[start] }

            let isVerticalRow = remaining.width >= remaining.height
            let thickness = CGFloat(rowArea / side)
            let strip = isVerticalRow
                ? CGRect(x: remaining.minX, y: remaining.minY, width: thickness, height: remaining.height)
                : CGRect(x: remaining.minX, y: remaining.minY, width: remaining.width, height: thickness)

            var offset: CGFloat = 0
            for index in start..<end {
                let fraction = rowArea > 0 ? CGFloat(areas[index] / rowArea) : 0
                if isVerticalRow {
                    let height = strip.height * fraction
                    frames[index] = CGRect(x: strip.minX, y: strip.minY + offset, width: strip.width, height: height)
                    offset += height
                } else {
                    let width = strip.width * fraction
                    frames[index] = CGRect(x: strip.minX + offset, y: strip.minY, width: width, height: strip.height)
                    offset += width
                }
            }

            remaining = isVerticalRow
                ? CGRect(x: remaining.minX + thickness, y: remaining.minY,
                         width: max(remaining.width - thickness, 0), height: remaining.height)
                : CGRect(x: remaining.minX, y: remaining.minY + thickness,
                         width: remaining.width, height: max(remaining.height - thickness, 0))
            start = end
        }
        return frames
    }

    /// Worst width-to-height ratio among the rectangles a row would produce.
    private static func worstAspectRatio(_ areas: ArraySlice<Double>, area: Double, side: Double) -> Double {
        guard area > 0, side > 0,
              let smallest = areas.min(), let largest = areas.max(), smallest > 0
        else { return .infinity }
        let sideSquared = side * side
        let areaSquared = area * area
        return max(sideSquared * largest / areaSquared, areaSquared / (sideSquared * smallest))
    }
}
