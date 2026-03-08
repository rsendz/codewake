//
//  OwnershipView.swift
//  codewake
//
//  Created by Luis Resendez on 08/03/2026.
//

import CodewakeKit
import SwiftUI

/// Assigns a legend colour to each author. The top few get a hue of their own; everyone
/// after that shares one neutral slate, because a map with forty colours on it is a map
/// with no colours on it.
struct AuthorColors {
    private let slots: [String: Int]

    init(_ report: OwnershipReport) {
        slots = Dictionary(
            uniqueKeysWithValues: report.authors
                .prefix(Palette.authorSlotCount)
                .enumerated()
                .map { ($0.element.name, $0.offset) }
        )
    }

    /// Nil for authors outside the legend.
    func slot(for name: String) -> Int? { slots[name] }

    func color(for name: String, strength: Double = 1) -> Color {
        Palette.author(slots[name], strength: strength)
    }
}

/// The ownership map: the same rectangles as the hotspot map, coloured by who owns each
/// file rather than by how risky it is.
///
/// The question it answers is where knowledge is concentrated. A block of one colour is a
/// region of the codebase one person has to themselves — fine while they are here, and a
/// gap the day they are not.
struct OwnershipView: View {
    let report: OwnershipReport
    let colors: AuthorColors
    /// True until the first report for this repository arrives. Without it the map claims
    /// the repository is empty for the moment before ownership has been counted.
    let isLoading: Bool
    let selection: FileID?
    /// When set, everything this author does not own is dimmed.
    let highlightedAuthor: String?
    let onSelect: (FileID?) -> Void

    /// Sized by lines, so the largest files fill the map. Past this the rectangles are
    /// slivers, and the summary in the inspector still counts every file.
    static let tileLimit = 250

    private var shown: ArraySlice<FileOwnership> { report.files.prefix(Self.tileLimit) }

    var body: some View {
        let index = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        TreemapCanvas(
            entries: shown.map { TreemapEntry(id: $0.id, path: $0.path, area: Double($0.lines)) },
            appearance: { tile, isHovered in
                appearance(for: index[tile.id], isHovered: isHovered)
            },
            onSelect: onSelect,
            tooltip: { tile in
                if let file = index[tile.id] { tooltip(for: file) }
            }
        )
        .overlay {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if report.files.isEmpty {
                emptyState
            }
        }
    }

    /// How strongly a file reads as belonging to its owner.
    ///
    /// Not the raw share: on a team of five, holding 40% of a file's commits is a real
    /// claim, and fading everything under half to grey painted almost the whole map as
    /// unowned. The scale starts just below an even two-way split and saturates at 85%,
    /// which leaves the neutral colour for files that genuinely belong to a committee.
    private func strength(_ file: FileOwnership) -> Double {
        min(max((file.share - 0.3) / 0.55, 0), 1)
    }

    private func appearance(for file: FileOwnership?, isHovered: Bool) -> TileAppearance {
        guard let file else { return TileAppearance(fill: .clear) }
        let isSelected = file.id == selection
        let strength = strength(file)

        // Highlighting an author dims the rest of the map rather than hiding it, the same
        // way a file search does — the surrounding shape is what makes the answer legible.
        var opacity = 1.0
        if let highlightedAuthor, file.owner != highlightedAuthor { opacity = 0.18 }

        var style = TileAppearance(
            fill: colors.color(for: file.owner, strength: strength).opacity(opacity),
            label: (strength > 0.62 ? Color.black.opacity(0.72) : Palette.primaryText).opacity(opacity)
        )
        if isSelected || isHovered {
            style.outline = (isSelected ? .white : .white.opacity(0.6), isSelected ? 2 : 1)
        }
        return style
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing here yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("Scrub forward to see who wrote the code as it appears.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faintText)
        }
    }

    private func tooltip(for file: FileOwnership) -> some View {
        TreemapTooltip {
            Text(file.path)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.primaryText)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.color(for: file.owner))
                    .frame(width: 7, height: 7)
                Text(file.isSoleAuthored
                     ? "\(file.owner) — the only author"
                     : "\(file.owner) — \(Int((file.share * 100).rounded()))% of \(file.commits.formatted()) commits, \(file.authorCount) authors")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }
}
