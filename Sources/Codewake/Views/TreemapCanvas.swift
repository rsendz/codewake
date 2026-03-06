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
    /// Called for every tile on every pass, with whether the pointer is over it.
    let appearance: (TreemapTile, Bool) -> TileAppearance
    let onSelect: (FileID?) -> Void
    @ViewBuilder let tooltip: (TreemapTile) -> Tooltip

    @State private var hovered: TreemapTile?
    @State private var pointer: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            // Laying out a few hundred rectangles is cheap enough to redo on each pass,
            // which keeps drawing and hit-testing working from the identical geometry.
            let groups = TreemapLayout.layout(
                entries: entries,
                in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 8, dy: 8)
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
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture { point in
                onSelect(tile(at: point, in: groups)?.id)
            }
            .overlay(alignment: .topLeading) {
                if let hovered { placed(tooltip(hovered), in: proxy.size) }
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
            context.draw(
                Text(group.id)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText),
                at: CGPoint(x: group.headerFrame.minX + 3, y: group.headerFrame.midY),
                anchor: .leading
            )
        }
    }

    // MARK: - Hit testing

    private func tile(at point: CGPoint, in groups: [TreemapGroup]) -> TreemapTile? {
        for group in groups where group.frame.contains(point) {
            return group.tiles.first { $0.frame.contains(point) }
        }
        return nil
    }

    /// Nudges the tooltip back inside the view when the pointer nears an edge.
    private func placed(_ tooltip: Tooltip, in size: CGSize) -> some View {
        tooltip
            .fixedSize()
            .offset(
                x: min(pointer.x + 12, max(size.width - 280, 0)),
                y: min(pointer.y + 12, max(size.height - 56, 0))
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
