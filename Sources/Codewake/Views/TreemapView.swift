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
        let index = Dictionary(hotspots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        TreemapCanvas(
            entries: hotspots.map {
                TreemapEntry(id: $0.id, path: $0.path, area: Double($0.file.approximateLines))
            },
            appearance: { tile, isHovered in
                appearance(for: index[tile.id], isHovered: isHovered)
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

    private func appearance(for hotspot: Hotspot?, isHovered: Bool) -> TileAppearance {
        guard let hotspot else { return TileAppearance(fill: .clear) }
        let relative = heat(hotspot.score)
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
