//
//  AgeView.swift
//  codewake
//
//  Created by Luis Resendez on 19/03/2026.
//

import CodewakeKit
import SwiftUI

/// The age map: the same rectangles as the hotspot map, coloured by how long it has been
/// since anyone touched each file.
///
/// The question it answers is which parts of the codebase are still alive. A bright region
/// is where the work is; a dark one is code that nobody has had a reason to open in years —
/// which is either the stable foundation or the part everyone is afraid of, and knowing
/// which is worth a conversation.
struct AgeView: View {
    let report: AgeReport
    let isLoading: Bool
    let selection: FileID?
    let depth: Int
    let pathPrefix: String
    let onSelect: (FileID?) -> Void
    let onOpen: (String) -> Void
    /// Whether small rectangles magnify on hover.
    let magnifies: Bool

    /// Same cap as the other maps: past this the rectangles are slivers and the summary in
    /// the inspector still counts every file.
    static let tileLimit = 250

    private var shown: ArraySlice<FileAge> {
        guard !pathPrefix.isEmpty else { return report.files.prefix(Self.tileLimit) }
        return report.files.filter { $0.path.hasPrefix(pathPrefix) }.prefix(Self.tileLimit)
    }

    var body: some View {
        let shown = self.shown
        let index = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scale = AgeScale(shown)

        TreemapCanvas(
            entries: shown.map { TreemapEntry(id: $0.id, path: $0.path, area: Double($0.lines)) },
            depth: depth,
            appearance: { tile, isHovered in
                appearance(for: index[tile.id], scale: scale, isHovered: isHovered)
            },
            onSelect: onSelect,
            onOpen: onOpen,
            magnifies: magnifies,
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

    private func appearance(for file: FileAge?, scale: AgeScale, isHovered: Bool) -> TileAppearance {
        guard let file else { return TileAppearance(fill: .clear) }
        let value = scale.value(of: file.id)
        var style = TileAppearance(
            fill: Palette.age(value),
            // The bright end of the ramp is light enough that white text disappears on it.
            label: value < 0.28 ? Color.black.opacity(0.72) : Palette.primaryText
        )
        if file.id == selection || isHovered {
            style.outline = (file.id == selection ? .white : .white.opacity(0.6), file.id == selection ? 2 : 1)
        }
        return style
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing here yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("Scrub forward to watch the codebase cool behind the playhead.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faintText)
        }
    }

    private func tooltip(for file: FileAge) -> some View {
        TreemapTooltip {
            Text(file.path)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.primaryText)
            Text("last touched \(Age.phrase(file.age)) · \(file.lines.formatted()) lines")
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

/// Ages are read at a glance, so they are spoken the way a person would say them rather
/// than printed to the day.
enum Age {
    static func phrase(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case ..<31: return "\(days) days ago"
        case ..<365:
            let months = max(days / 30, 1)
            return months == 1 ? "a month ago" : "\(months) months ago"
        default:
            let years = Double(days) / 365
            return years < 1.5 ? "a year ago" : "\(years.formatted(.number.precision(.fractionLength(1)))) years ago"
        }
    }

    /// Without "ago", for labelling a duration rather than a moment.
    static func span(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86_400)
        switch days {
        case ..<1: return "under a day"
        case ..<31: return "\(days)d"
        case ..<365: return "\(max(days / 30, 1))mo"
        default: return "\((Double(days) / 365).formatted(.number.precision(.fractionLength(1))))y"
        }
    }
}

/// Turns ages into positions on the age ramp.
///
/// Measuring a file's age purely as a share of the repository's lifetime is the honest
/// scale and a useless picture: most files in a young codebase were written at roughly the
/// same time and never revisited, so they all land on the same stop and the map comes out
/// one flat colour. The point of the view is which parts stopped *first*, and that is a
/// question about order.
///
/// So rank among the files on screen carries most of the weight, and the absolute share
/// keeps the rest — enough that a codebase where genuinely everything is recent still reads
/// as bright rather than being darkened just to fill the ramp.
struct AgeScale {
    private let values: [FileID: Double]

    private static let rankWeight = 0.55

    init(_ files: some Collection<FileAge>) {
        let ranked = files.sorted { $0.age < $1.age }
        let last = Double(max(ranked.count - 1, 1))
        values = Dictionary(
            ranked.enumerated().map { offset, file in
                let rank = Double(offset) / last
                return (file.id, rank * Self.rankWeight + file.share * (1 - Self.rankWeight))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func value(of id: FileID) -> Double { values[id] ?? 0 }
}
