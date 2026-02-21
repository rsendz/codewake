//
//  TimelineView.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CodewakerKit
import SwiftUI

/// The scrubber: commit activity over time, with a playhead you drag through history.
struct TimelineView: View {
    let commits: [CommitSummary]
    let commitIndex: Int
    let isPlaying: Bool
    let onScrub: (Int) -> Void
    let onTogglePlayback: () -> Void

    private static let trackHeight: CGFloat = 54

    var body: some View {
        VStack(spacing: 6) {
            header
            track
            axis
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .panelBackground()
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.borderless)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
            .foregroundStyle(Palette.primaryText)
            .help(isPlaying ? "Pause" : "Play history")

            if let commit = commits[safe: commitIndex] {
                Text(commit.shortSHA)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.faintText)
                Text(commit.subject)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(commit.authorName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                Text(commit.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.faintText)
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Track

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let bars = activityBars(width: width)
            let playheadX = position(of: commitIndex, width: width)

            Canvas { context, size in
                // Everything up to the playhead is "already happened", which gives the
                // scrubber an obvious direction of travel.
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: playheadX, height: size.height)),
                    with: .color(Color.white.opacity(0.05))
                )

                for bar in bars {
                    let barHeight = max(1.5, bar.magnitude * (size.height - 4))
                    context.fill(
                        Path(CGRect(
                            x: bar.x, y: size.height - barHeight,
                            width: bar.width, height: barHeight
                        )),
                        with: .color(bar.x <= playheadX ? Palette.accent.opacity(0.75) : Color.white.opacity(0.22))
                    )
                }

                context.fill(
                    Path(CGRect(x: playheadX - 1, y: 0, width: 2, height: size.height)),
                    with: .color(.white)
                )
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onScrub(index(at: value.location.x, width: width)) }
            )
        }
        .frame(height: Self.trackHeight)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.28)))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var axis: some View {
        HStack {
            Text(commits.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
            Spacer()
            Text("commit \((commitIndex + 1).formatted()) of \(commits.count.formatted())")
            Spacer()
            Text(commits.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
        }
        .font(.system(size: 10))
        .foregroundStyle(Palette.faintText)
    }

    // MARK: - Geometry

    private struct Bar {
        let x: CGFloat
        let width: CGFloat
        /// 0...1 height, already log-scaled.
        let magnitude: Double
    }

    /// One bar per few pixels rather than per commit: a repository with 40,000 commits has
    /// far more commits than the track has columns, and drawing them all would be a smear.
    private func activityBars(width: CGFloat) -> [Bar] {
        guard width > 0, !commits.isEmpty else { return [] }
        let columnWidth: CGFloat = 3
        let columns = max(1, Int(width / columnWidth))
        var totals = [Int](repeating: 0, count: columns)

        for (index, commit) in commits.enumerated() {
            let column = min(columns - 1, index * columns / commits.count)
            totals[column] += commit.churn
        }

        // Churn per column spans orders of magnitude; a linear scale would show one spike
        // from a vendored-dependency commit and flatten everything else to nothing.
        let peak = log1p(Double(totals.max() ?? 0))
        guard peak > 0 else { return [] }

        return totals.enumerated().map { column, total in
            Bar(
                x: CGFloat(column) * columnWidth,
                width: columnWidth - 1,
                magnitude: log1p(Double(total)) / peak
            )
        }
    }

    private func position(of index: Int, width: CGFloat) -> CGFloat {
        guard commits.count > 1 else { return 0 }
        return CGFloat(index) / CGFloat(commits.count - 1) * width
    }

    private func index(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let fraction = min(max(x / width, 0), 1)
        return Int((fraction * CGFloat(commits.count - 1)).rounded())
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
