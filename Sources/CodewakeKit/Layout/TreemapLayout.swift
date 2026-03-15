//
//  TreemapLayout.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CoreGraphics
import Foundation

/// One file reduced to what the layout actually needs: an identity, a path to group and
/// label it by, and an area. Keeping the layout blind to the rest means the same geometry
/// serves the hotspot map and the ownership map, and each view looks up its own model by
/// id rather than the layout carrying both.
public struct TreemapEntry: Sendable, Identifiable, Hashable {
    public let id: FileID
    public let path: String
    public let area: Double

    public init(id: FileID, path: String, area: Double) {
        self.id = id
        self.path = path
        self.area = area
    }
}

public struct TreemapTile: Sendable, Identifiable {
    public let entry: TreemapEntry
    public let frame: CGRect

    public var id: FileID { entry.id }
    public var path: String { entry.path }
    public var name: String { String(entry.path.split(separator: "/").last ?? "") }
}

public struct TreemapGroup: Sendable, Identifiable {
    /// The directory this group names, or "/" for the loose files at the current level.
    public let id: String
    public let frame: CGRect
    /// Strip along the top of `frame` reserved for the group's label, empty when the group
    /// is too small to letter.
    public let headerFrame: CGRect
    public let tiles: [TreemapTile]

    public var showsHeader: Bool { !headerFrame.isEmpty }

    /// Whether opening this group would show something different. "/" is the files already
    /// on screen and "other" is a fold of unrelated directories; neither is a real place.
    public var isOpenable: Bool {
        id != "/" && id != TreemapLayout.otherGroupName
    }
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

    /// The smallest a tile may be drawn, in points².
    ///
    /// Sizing by raw line count is honest and unreadable at the small end: a 20-line file
    /// beside a 2,000-line one is 1% of its area, which at window size is a handful of
    /// pixels — under the threshold where a rectangle is drawn at all, so the file silently
    /// vanished from a view whose whole claim is that it shows every file that exists.
    ///
    /// The obvious fix is to compress every area with an exponent, and it is the wrong one:
    /// it flattens the entire range to repair only the tail, so the largest file stops
    /// reading as the largest. Lifting just the tail costs the big files almost nothing —
    /// on a 250-tile map of a real repository the biggest tile gives up a tenth of a percent
    /// of its area — because the whole deficit is measured in pixels and they are measured
    /// in thousands.
    ///
    /// 12×12 points: too small to letter, big enough to see, to hover, and to click.
    public static let minimumTileArea: Double = 144

    /// Scales `areas` to fill `total`, then lifts everything under `minimum` up to it and
    /// takes the difference from the tiles that have room to spare, in proportion to how
    /// much spare they have. Repeated until nothing is under the floor, since paying for
    /// the lift can push a tile that was just above it below.
    ///
    /// The floor cannot exceed the mean — if every tile wants the minimum there is nothing
    /// to take it from — which is what makes this safe on a map of a hundred tiny files.
    static func fittedAreas(_ areas: [Double], filling total: Double, minimum: Double) -> [Double] {
        let sum = areas.reduce(0, +)
        guard !areas.isEmpty, total > 0, sum > 0 else { return areas }
        let floor = min(minimum, total / Double(areas.count))
        var fitted = areas.map { $0 * total / sum }

        for _ in 0..<8 {
            let deficit = fitted.reduce(0) { $0 + max(floor - $1, 0) }
            guard deficit > 0 else { break }
            let surplus = fitted.reduce(0) { $0 + max($1 - floor, 0) }
            guard surplus > deficit else { break }
            let factor = (surplus - deficit) / surplus
            fitted = fitted.map { $0 <= floor ? floor : floor + ($0 - floor) * factor }
        }
        return fitted
    }

    public static func layout(
        hotspots: [Hotspot],
        in bounds: CGRect,
        depth: Int = 0,
        headerHeight: CGFloat = 16,
        padding: CGFloat = 2
    ) -> [TreemapGroup] {
        layout(
            entries: hotspots.map {
                TreemapEntry(id: $0.id, path: $0.path, area: Double($0.file.approximateLines))
            },
            in: bounds, depth: depth, headerHeight: headerHeight, padding: padding
        )
    }

    /// `depth` is which path component names the groups: 0 for top-level directories, 1 once
    /// the view has been opened into one of them, and so on. Callers pass entries already
    /// filtered to the directory being shown, so the layout never has to know the path it is
    /// inside — only how far down it is.
    public static func layout(
        entries: [TreemapEntry],
        in bounds: CGRect,
        depth: Int = 0,
        headerHeight: CGFloat = 16,
        padding: CGFloat = 2
    ) -> [TreemapGroup] {
        guard !entries.isEmpty, bounds.width > 1, bounds.height > 1 else { return [] }

        // Areas are resolved against the whole canvas once, so a file is the same size
        // whichever group it lands in and the floor means the same thing everywhere.
        let fitted = fittedAreas(
            entries.map(area(of:)),
            filling: Double(bounds.width) * Double(bounds.height),
            minimum: minimumTileArea
        )
        let groups = group(zip(entries, fitted).map { (entry: $0, area: $1) }, depth: depth)
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

            let sorted = group.entries.sorted { $0.area > $1.area }
            let tileFrames = squarify(sorted.map(\.area), in: content)
            let tiles = zip(sorted, tileFrames).compactMap { member, tileFrame -> TreemapTile? in
                let inset = tileFrame.insetBy(dx: 0.5, dy: 0.5)
                guard inset.width > 1, inset.height > 1 else { return nil }
                return TreemapTile(entry: member.entry, frame: inset)
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
    private static func area(of entry: TreemapEntry) -> Double {
        max(entry.area, 1)
    }

    // MARK: - Grouping

    /// An entry paired with the area it was actually allotted, once the floor was applied.
    typealias Member = (entry: TreemapEntry, area: Double)

    private struct Group {
        let name: String
        var entries: [Member]
        var value: Double
    }

    private static func group(_ members: [Member], depth: Int) -> [Group] {
        var groups: [String: Group] = [:]
        for member in members {
            let components = member.entry.path.split(separator: "/")
            // A file sitting directly in the directory being shown has no subdirectory to
            // name it, so it joins the "/" group alongside the other loose files.
            let name = components.count > depth + 1 ? String(components[depth]) : "/"
            groups[name, default: Group(name: name, entries: [], value: 0)].entries.append(member)
            // A group is exactly as big as the tiles it has to contain.
            groups[name]!.value += member.area
        }

        let sorted = groups.values.sorted { ($0.value, $1.name) > ($1.value, $0.name) }
        guard sorted.count > maximumGroups else { return sorted }

        let kept = Array(sorted.prefix(maximumGroups - 1))
        let folded = sorted.dropFirst(maximumGroups - 1)
        let other = Group(
            name: otherGroupName,
            entries: folded.flatMap(\.entries),
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
