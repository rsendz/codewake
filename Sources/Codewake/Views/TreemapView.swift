//
//  TreemapView.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CodewakeKit
import SwiftUI

/// The hotspot map: every file that exists right now, sized by length, coloured by how
/// risky it is to touch, grouped by top-level directory.
struct TreemapView: View {
    let hotspots: [Hotspot]
    let selection: FileID?
    /// Partner files of the selection, by coupling strength. Drawn as outlines so a
    /// selected file's hidden relationships become visible across the whole map.
    let coupled: [FileID: Double]
    /// Files matching the search box, or nil when nothing is being searched.
    let searchMatches: Set<FileID>?
    let onSelect: (FileID?) -> Void

    @State private var hovered: TreemapTile?
    @State private var pointer: CGPoint = .zero

    /// Colour is relative to the hottest file currently on screen. An absolute scale would
    /// leave early history — when nothing has accumulated much churn yet — a uniform slab
    /// of cold blue with no shape to read.
    private var peakScore: Double {
        max(hotspots.first?.score ?? 0, 0.0001)
    }

    /// Both inputs to the score are log-normalised, which is what keeps one outlier from
    /// flattening the ranking — but it also means a file with a fraction of the peak's
    /// churn still scores past the middle. Colouring straight off that leaves most of the
    /// map warm and says nothing. This curve pushes the mass back down so only files near
    /// the top of the range read as hot, which is the whole point of the view.
    private func heat(_ score: Double) -> Double {
        pow(score / peakScore, 2.2)
    }

    var body: some View {
        GeometryReader { proxy in
            // Laying out a few hundred rectangles is cheap enough to redo on each pass,
            // which keeps drawing and hit-testing working from the identical geometry.
            let groups = TreemapLayout.layout(
                hotspots: hotspots,
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
                if let hovered { tooltip(for: hovered, in: proxy.size) }
            }
        }
        .background(Palette.canvas)
        .overlay {
            if hotspots.isEmpty { emptyState }
        }
    }

    // MARK: - Drawing

    private func draw(_ group: TreemapGroup, in context: inout GraphicsContext) {
        context.fill(
            Path(roundedRect: group.frame, cornerRadius: 4),
            with: .color(Palette.groupFill)
        )

        for tile in group.tiles {
            let relative = heat(tile.hotspot.score)
            let isSelected = tile.id == selection
            let isHovered = tile.id == hovered?.id
            let couplingDegree = coupled[tile.id]

            // A search dims everything it does not match, rather than hiding it: the map's
            // shape is the context that makes a match meaningful.
            var opacity = tile.hotspot.isEstimated ? 0.72 : 1.0
            if let searchMatches, !searchMatches.contains(tile.id) { opacity *= 0.22 }

            context.fill(
                Path(roundedRect: tile.frame, cornerRadius: 1.5),
                with: .color(Palette.hotspot(relative).opacity(opacity))
            )

            if let couplingDegree, !isSelected {
                context.stroke(
                    Path(roundedRect: tile.frame.insetBy(dx: -0.5, dy: -0.5), cornerRadius: 2),
                    with: .color(Palette.coupling.opacity(0.45 + couplingDegree * 0.55)),
                    lineWidth: 1.5
                )
            }
            if isSelected || isHovered {
                context.stroke(
                    Path(roundedRect: tile.frame.insetBy(dx: -0.5, dy: -0.5), cornerRadius: 2),
                    with: .color(isSelected ? .white : .white.opacity(0.6)),
                    lineWidth: isSelected ? 2 : 1
                )
            }
            // Only label a rectangle with room for a legible name; anything smaller becomes
            // texture, and the inspector is there for the detail.
            if tile.frame.width > 54, tile.frame.height > 15 {
                context.draw(
                    Text(tile.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(
                            (relative > 0.5 ? Color.black.opacity(0.75) : Palette.primaryText)
                                .opacity(opacity)
                        ),
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing here yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("Scrub forward to watch the codebase appear.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faintText)
        }
    }

    // MARK: - Hit testing

    private func tile(at point: CGPoint, in groups: [TreemapGroup]) -> TreemapTile? {
        for group in groups where group.frame.contains(point) {
            return group.tiles.first { $0.frame.contains(point) }
        }
        return nil
    }

    private func tooltip(for tile: TreemapTile, in size: CGSize) -> some View {
        let hotspot = tile.hotspot
        return VStack(alignment: .leading, spacing: 2) {
            Text(hotspot.path)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.primaryText)
            Text("\(hotspot.file.churn.formatted()) lines churned · \(hotspot.file.commitCount.formatted()) commits · \(hotspot.file.approximateLines.formatted()) lines")
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondaryText)
            if let degree = coupled[tile.id] {
                Text("changes with the selected file \(Int((degree * 100).rounded()))% of the time")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.coupling)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline))
        .fixedSize()
        // Nudge the tooltip back inside the view when the pointer nears an edge.
        .offset(
            x: min(pointer.x + 12, max(size.width - 260, 0)),
            y: min(pointer.y + 12, max(size.height - 50, 0))
        )
        .allowsHitTesting(false)
    }
}
