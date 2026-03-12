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

    var body: some View {
        let index = Dictionary(hotspots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Built once per pass, not once per tile: it ranks the whole array.
        let scale = HeatScale(hotspots)

        TreemapCanvas(
            entries: hotspots.map {
                TreemapEntry(id: $0.id, path: $0.path, area: Double($0.file.approximateLines))
            },
            appearance: { tile, isHovered in
                appearance(for: index[tile.id], scale: scale, isHovered: isHovered)
            },
            onSelect: onSelect,
            tooltip: { tile in
                if let hotspot = index[tile.id] { tooltip(for: hotspot) }
            }
        )
        .overlay {
            if hotspots.isEmpty { emptyState }
        }
    }

    private func appearance(for hotspot: Hotspot?, scale: HeatScale, isHovered: Bool) -> TileAppearance {
        guard let hotspot else { return TileAppearance(fill: .clear) }
        let relative = scale.heat(of: hotspot.id)
        let isSelected = hotspot.id == selection

        // A search dims everything it does not match, rather than hiding it: the map's
        // shape is the context that makes a match meaningful.
        var opacity = hotspot.isEstimated ? 0.72 : 1.0
        if let searchMatches, !searchMatches.contains(hotspot.id) { opacity *= 0.22 }

        var style = TileAppearance(
            fill: Palette.hotspot(relative).opacity(opacity),
            label: (relative > 0.5 ? Color.black.opacity(0.75) : Palette.primaryText).opacity(opacity)
        )
        if isSelected || isHovered {
            style.outline = (isSelected ? .white : .white.opacity(0.6), isSelected ? 2 : 1)
        } else if let degree = coupled[hotspot.id] {
            style.outline = (Palette.coupling.opacity(0.45 + degree * 0.55), 1.5)
        }
        return style
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

    private func tooltip(for hotspot: Hotspot) -> some View {
        TreemapTooltip {
            Text(hotspot.path)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.primaryText)
            Text("\(hotspot.file.churn.formatted()) lines churned · \(hotspot.file.commitCount.formatted()) commits · \(hotspot.file.approximateLines.formatted()) lines")
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondaryText)
            if let degree = coupled[hotspot.id] {
                Text("changes with the selected file \(Int((degree * 100).rounded()))% of the time")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.coupling)
            }
        }
    }
}

/// Turns hotspot scores into positions on the colour ramp.
///
/// Dividing by the hottest file on screen — the obvious thing, and what this used to do —
/// ties the whole map to a single order statistic. On a large repository one runaway file
/// sets the peak and everything else collapses into the cold end; on a small one there is
/// no runaway file, so the same divisor leaves the map washed out. Either way the amount of
/// the map that reads as hot depends on the repository rather than on the code.
///
/// So rank carries most of the weight: a file's position among the files on screen, curved
/// so that being near the top is what earns a warm colour rather than being merely above
/// the middle. That fixes the proportions at any size. The peak-relative score keeps a
/// minority share, because rank alone would flatten a genuine outlier into "first" and
/// invent separation between files that actually score the same.
struct HeatScale {
    /// Rank in the on-screen ordering, 1 for the hottest file, 0 for the coldest.
    private let ranks: [FileID: Double]
    private let scores: [FileID: Double]
    private let peak: Double

    /// How sharply rank has to approach the top to read as hot. At 2.5 roughly the top
    /// twentieth of files are red and the top fifth are warm, whatever the repository.
    private static let rankCurve = 2.5
    private static let rankWeight = 0.6

    /// `hotspots` arrives sorted hottest first, which is the ranking.
    init(_ hotspots: [Hotspot]) {
        peak = max(hotspots.first?.score ?? 0, 0.0001)
        let last = Double(max(hotspots.count - 1, 1))
        ranks = Dictionary(
            hotspots.enumerated().map { ($0.element.id, 1 - Double($0.offset) / last) },
            uniquingKeysWith: { first, _ in first }
        )
        scores = Dictionary(
            hotspots.map { ($0.id, $0.score) }, uniquingKeysWith: { first, _ in first }
        )
    }

    func heat(of id: FileID) -> Double {
        guard let rank = ranks[id], let score = scores[id] else { return 0 }
        let byRank = pow(rank, Self.rankCurve)
        let byScore = pow(score / peak, 2.2)
        return byRank * Self.rankWeight + byScore * (1 - Self.rankWeight)
    }
}
