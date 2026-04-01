//
//  TreemapCanvas.swift
//  codewake
//
//  Created by Luis Resendez on 05/03/2026.
//

import CodewakeKit
import SwiftUI

/// How one tile should be drawn. The canvas owns geometry, hover and hit-testing; the map
/// using it owns what the colours mean.
struct TileAppearance {
    var fill: Color
    var outline: (color: Color, width: CGFloat)?
    /// Colour for the file's name, when the rectangle is large enough to carry one.
    var label: Color

    init(fill: Color, outline: (color: Color, width: CGFloat)? = nil, label: Color = .white) {
        self.fill = fill
        self.outline = outline
        self.label = label
    }
}

/// The treemap itself: squarified rectangles grouped by top-level directory, with hover,
/// selection and a tooltip.
///
/// Two maps are drawn this way — hotspots and ownership. They choose their own files and
/// their own colours, but everything about how a rectangle is placed, grouped, labelled and
/// hit-tested lives here once, so the two read as the same kind of picture rather than as
/// two views that happen to both use squares.
struct TreemapCanvas<Tooltip: View>: View {
    let entries: [TreemapEntry]
    /// How deep into the directory tree the view is currently opened. Groups are named by
    /// the path component at this index.
    var depth: Int = 0
    /// Called for every tile on every pass, with whether the pointer is over it.
    let appearance: (TreemapTile, Bool) -> TileAppearance
    let onSelect: (FileID?) -> Void
    /// Clicking a directory's header opens it. Nil leaves headers inert.
    var onOpen: ((String) -> Void)?
    /// Whether hovering a rectangle too small to carry a name magnifies the area around it.
    var magnifies: Bool = true
    @ViewBuilder let tooltip: (TreemapTile) -> Tooltip

    @State private var hovered: TreemapTile?
    @State private var hoveredHeader: String?
    @State private var pointer: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            // Laying out a few hundred rectangles is cheap enough to redo on each pass,
            // which keeps drawing and hit-testing working from the identical geometry.
            let groups = TreemapLayout.layout(
                entries: entries,
                in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 8, dy: 8),
                depth: depth
            )

            Canvas { context, _ in
                for group in groups { draw(group, in: &context) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    pointer = point
                    hovered = tile(at: point, in: groups)
                    hoveredHeader = openableHeader(at: point, in: groups)?.id
                case .ended:
                    hovered = nil
                    hoveredHeader = nil
                }
            }
            .onTapGesture { point in
                // A directory's header opens it; anywhere else selects a file.
                if let onOpen, let group = openableHeader(at: point, in: groups) {
                    onOpen(group.id)
                } else {
                    onSelect(tile(at: point, in: groups)?.id)
                }
            }
            .overlay(alignment: .topLeading) {
                if let hovered {
                    // A tile too small to carry a name gets the magnified view above the
                    // tooltip, as one panel: what is under the pointer, and what is around
                    // it. Two separate floating cards would overlap each other.
                    if magnifies, isTooSmallToLabel(hovered) {
                        placed(
                            VStack(alignment: .leading, spacing: 0) {
                                loupe(around: pointer, in: groups)
                                tooltip(hovered)
                                    .frame(width: loupeSize.width, alignment: .leading)
                            }
                            .background(Color.black.opacity(0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline))
                            .shadow(color: .black.opacity(0.5), radius: 10, y: 3),
                            in: proxy.size,
                            size: CGSize(width: loupeSize.width, height: loupeSize.height + 56)
                        )
                    } else {
                        placed(tooltip(hovered), in: proxy.size)
                    }
                }
            }
        }
        .background(Palette.canvas)
    }

    // MARK: - Drawing

    private func draw(_ group: TreemapGroup, in context: inout GraphicsContext) {
        context.fill(
            Path(roundedRect: group.frame, cornerRadius: 4),
            with: .color(Palette.groupFill)
        )

        for tile in group.tiles {
            let style = appearance(tile, tile.id == hovered?.id)

            context.fill(
                Path(roundedRect: tile.frame, cornerRadius: 1.5),
                with: .color(style.fill)
            )
            if let outline = style.outline {
                context.stroke(
                    Path(roundedRect: tile.frame.insetBy(dx: -0.5, dy: -0.5), cornerRadius: 2),
                    with: .color(outline.color),
                    lineWidth: outline.width
                )
            }
            // Only label a rectangle with room for a legible name; anything smaller becomes
            // texture, and the inspector is there for the detail.
            if tile.frame.width > 54, tile.frame.height > 15 {
                context.draw(
                    Text(tile.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(style.label),
                    in: tile.frame.insetBy(dx: 3, dy: 2)
                )
            }
        }

        if group.showsHeader {
            // A header the pointer is over and that can be opened lights up, which is the
            // only affordance saying the map goes deeper than what is on screen.
            let isOpenable = onOpen != nil && group.isOpenable
            let isHovered = isOpenable && group.id == hoveredHeader
            context.draw(
                Text(group.id + (isHovered ? " ›" : ""))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovered ? Palette.accent : Palette.secondaryText),
                at: CGPoint(x: group.headerFrame.minX + 3, y: group.headerFrame.midY),
                anchor: .leading
            )
        }
    }

    // MARK: - Loupe

    /// Size of the magnified panel, and how much of the map it covers.
    private var loupeSize: CGSize { CGSize(width: 300, height: 210) }
    private var magnification: CGFloat { 3.2 }

    private func isTooSmallToLabel(_ tile: TreemapTile) -> Bool {
        tile.frame.width <= 54 || tile.frame.height <= 15
    }

    /// A magnified window onto the map around the pointer.
    ///
    /// At repository scale the smallest files are a few points across: they are drawn, and
    /// they are the right colour, but they carry no name, so a dense corner reads as texture
    /// rather than as files. This magnifies that corner in place — same rectangles, same
    /// colours, same arrangement, just large enough to letter — so the answer to "what are
    /// these" does not cost a navigation.
    private func loupe(around point: CGPoint, in groups: [TreemapGroup]) -> some View {
        let scale = magnification
        let source = CGRect(
            x: point.x - loupeSize.width / (2 * scale),
            y: point.y - loupeSize.height / (2 * scale),
            width: loupeSize.width / scale,
            height: loupeSize.height / scale
        )

        return Canvas { context, _ in
            context.fill(
                Path(CGRect(origin: .zero, size: loupeSize)),
                with: .color(Palette.canvas)
            )
            for group in groups where group.frame.intersects(source) {
                for tile in group.tiles where tile.frame.intersects(source) {
                    let frame = CGRect(
                        x: (tile.frame.minX - source.minX) * scale,
                        y: (tile.frame.minY - source.minY) * scale,
                        width: tile.frame.width * scale,
                        height: tile.frame.height * scale
                    )
                    let style = appearance(tile, tile.id == hovered?.id)
                    context.fill(Path(roundedRect: frame, cornerRadius: 2), with: .color(style.fill))
                    if tile.id == hovered?.id {
                        context.stroke(
                            Path(roundedRect: frame.insetBy(dx: -0.5, dy: -0.5), cornerRadius: 2.5),
                            with: .color(.white), lineWidth: 1.5
                        )
                    }
                    if frame.width > 34, frame.height > 13 {
                        context.draw(
                            Text(tile.name)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(style.label),
                            in: frame.insetBy(dx: 2, dy: 1)
                        )
                    }
                }
            }
        }
        .frame(width: loupeSize.width, height: loupeSize.height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
        .allowsHitTesting(false)
    }

    // MARK: - Hit testing

    /// The group whose header strip is under `point`, when that group can be opened.
    private func openableHeader(at point: CGPoint, in groups: [TreemapGroup]) -> TreemapGroup? {
        groups.first { $0.showsHeader && $0.isOpenable && $0.headerFrame.contains(point) }
    }

    private func tile(at point: CGPoint, in groups: [TreemapGroup]) -> TreemapTile? {
        for group in groups where group.frame.contains(point) {
            return group.tiles.first { $0.frame.contains(point) }
        }
        return nil
    }

    /// Nudges a floating panel back inside the view when the pointer nears an edge.
    private func placed(
        _ panel: some View,
        in size: CGSize,
        size panelSize: CGSize = CGSize(width: 280, height: 56)
    ) -> some View {
        panel
            .fixedSize()
            .offset(
                x: min(pointer.x + 12, max(size.width - panelSize.width, 0)),
                y: min(pointer.y + 12, max(size.height - panelSize.height, 0))
            )
            .allowsHitTesting(false)
    }
}

/// Shared tooltip chrome, so both maps float the same card.
struct TreemapTooltip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { content }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline))
    }
}
