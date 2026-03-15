//
//  OwnershipView.swift
//  codewake
//
//  Created by Luis Resendez on 08/03/2026.
//

import CodewakeKit
import SwiftUI

/// Assigns a legend colour to each author. The busiest few get a hue of their own; everyone
/// after that shares one neutral slate, because a map with forty colours on it is a map
/// with no colours on it.
///
/// Built once per repository from `RepositorySummary.authorRanking`, never from the report
/// at the current position. The report ranks people by what they own *here*, and that order
/// changes as the playhead moves — colouring from it made files change colour mid-scrub for
/// reasons unrelated to ownership.
struct AuthorColors {
    private let slots: [String: Int]
    let slotCount: Int

    init(ranking: [String]) {
        slotCount = Palette.authorSlotCount(forAuthors: ranking.count)
        slots = Dictionary(
            uniqueKeysWithValues: ranking.prefix(slotCount).enumerated().map { ($0.element, $0.offset) }
        )
    }

    /// Nil for authors outside the legend.
    func slot(for name: String) -> Int? { slots[name] }

    func color(for name: String, strength: Double = 1) -> Color {
        Palette.author(slots[name], of: slotCount, strength: strength)
    }

    func color(slot: Int) -> Color { Palette.author(slot, of: slotCount) }
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
    let depth: Int
    /// Path prefix of the directory the map is opened into; empty for the whole repository.
    let pathPrefix: String
    let onSelect: (FileID?) -> Void
    let onOpen: (String) -> Void

    /// Sized by lines, so the largest files fill the map. Past this the rectangles are
    /// slivers, and the summary in the inspector still counts every file.
    static let tileLimit = 250

    private var shown: ArraySlice<FileOwnership> {
        guard !pathPrefix.isEmpty else { return report.files.prefix(Self.tileLimit) }
        return report.files.filter { $0.path.hasPrefix(pathPrefix) }.prefix(Self.tileLimit)
    }

    var body: some View {
        let index = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        TreemapCanvas(
            entries: shown.map { TreemapEntry(id: $0.id, path: $0.path, area: Double($0.lines)) },
            depth: depth,
            appearance: { tile, isHovered in
                appearance(for: index[tile.id], isHovered: isHovered)
            },
            onSelect: onSelect,
            onOpen: onOpen,
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
    /// Not the raw share, and not a fixed threshold either. An even split between everyone
    /// who touched the file is `1 / authorCount`, and that is the point where nobody owns
    /// it — on a two-person file 30% is nothing, on a twenty-person file it is dominance.
    /// So the scale starts just above an even split and saturates most of the way to sole
    /// authorship, which means "owns it" reads the same on a pair as on a large team.
    private func strength(_ file: FileOwnership) -> Double {
        let even = 1 / Double(max(file.authorCount, 1))
        let floor = even * 1.15
        let ceiling = even + (1 - even) * 0.75
        guard ceiling > floor else { return 1 }
        return min(max((file.share - floor) / (ceiling - floor), 0), 1)
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
