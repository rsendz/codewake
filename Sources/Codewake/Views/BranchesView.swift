//
//  BranchesView.swift
//  codewake
//
//  Created by Luis Resendez on 28/02/2026.
//

import CodewakeKit
import SwiftUI

/// Branches as a Gantt chart: time runs left to right, each bar is a line of work from its
/// first commit to the day it merged.
///
/// The point is to make shape visible — whether branches are short and frequent or long
/// and overlapping, when a big one was in flight, how much of the codebase it moved.
struct BranchesView: View {
    let branches: [Branch]
    let dateRange: ClosedRange<Date>
    let selection: Branch.ID?
    /// Where the timeline playhead currently sits, drawn across the chart so the two views
    /// stay tied together.
    let playheadDate: Date?
    let onSelect: (Branch.ID?) -> Void

    @State private var hovered: Branch?
    @State private var pointer: CGPoint = .zero

    private static let axisHeight: CGFloat = 22
    private static let laneRange: ClosedRange<CGFloat> = 17...34

    /// Bars are coloured by churn so the eye lands on the branches that moved the most
    /// code, using the same ramp as the map.
    private var peakChurn: Double {
        max(Double(branches.map(\.churn).max() ?? 0), 1)
    }

    var body: some View {
        if branches.isEmpty {
            emptyState
        } else {
            chart
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 22))
                .foregroundStyle(Palette.faintText)
            Text("No merged branches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("This repository's history is a straight line, so there is nothing to chart here.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faintText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }

    private var chart: some View {
        let lanes = assignBranchLanes(branches)
        let laneCount = (lanes.values.max() ?? 0) + 1

        return GeometryReader { proxy in
            let width = proxy.size.width - 24
            // Rows grow to fill the space when a repository has few branches, and stop
            // shrinking once they are too thin to click.
            let available = proxy.size.height - Self.axisHeight - 24
            let laneHeight = min(
                max(available / CGFloat(laneCount), Self.laneRange.lowerBound),
                Self.laneRange.upperBound
            )
            let bars = layout(lanes: lanes, width: width, laneHeight: laneHeight)

            ScrollView {
                Canvas { context, size in
                    draw(bars: bars, in: &context, size: size)
                }
                .frame(width: width, height: CGFloat(laneCount) * laneHeight + 8)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        pointer = point
                        hovered = bars.first { $0.frame.insetBy(dx: -2, dy: -3).contains(point) }?.branch
                    case .ended:
                        hovered = nil
                    }
                }
                .onTapGesture { point in
                    onSelect(bars.first { $0.frame.insetBy(dx: -2, dy: -3).contains(point) }?.branch.id)
                }
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if let hovered { tooltip(for: hovered, in: proxy.size) }
                }
            }
            .background(Palette.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) { axis }
        }
    }

    // MARK: - Layout

    private struct Bar {
        let branch: Branch
        let frame: CGRect
    }

    private func x(for date: Date, width: CGFloat) -> CGFloat {
        let span = dateRange.upperBound.timeIntervalSince(dateRange.lowerBound)
        guard span > 0 else { return 0 }
        let offset = date.timeIntervalSince(dateRange.lowerBound) / span
        return CGFloat(min(max(offset, 0), 1)) * width
    }

    private func layout(lanes: [Branch.ID: Int], width: CGFloat, laneHeight: CGFloat) -> [Bar] {
        branches.map { branch in
            let start = x(for: branch.startDate, width: width)
            let end = x(for: branch.mergeDate, width: width)
            let lane = CGFloat(lanes[branch.id] ?? 0)
            return Bar(
                branch: branch,
                frame: CGRect(
                    x: start,
                    y: lane * laneHeight + 3,
                    // A branch that opened and merged the same hour would otherwise be
                    // invisible, so every bar keeps a minimum clickable width.
                    width: max(end - start, 3),
                    height: laneHeight - 6
                )
            )
        }
    }

    // MARK: - Drawing

    private func draw(bars: [Bar], in context: inout GraphicsContext, size: CGSize) {
        if let playheadDate {
            let x = x(for: playheadDate, width: size.width)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: x, height: size.height)),
                with: .color(.white.opacity(0.04))
            )
            context.fill(
                Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)),
                with: .color(.white.opacity(0.5))
            )
        }

        for bar in bars {
            let heat = Double(bar.branch.churn) / peakChurn
            let isSelected = bar.branch.id == selection
            let isHovered = bar.branch.id == hovered?.id

            context.fill(
                Path(roundedRect: bar.frame, cornerRadius: 3),
                with: .color(Palette.hotspot(pow(heat, 0.55)).opacity(isSelected || isHovered ? 1 : 0.85))
            )
            if isSelected || isHovered {
                context.stroke(
                    Path(roundedRect: bar.frame.insetBy(dx: -1, dy: -1), cornerRadius: 4),
                    with: .color(isSelected ? .white : .white.opacity(0.55)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }

            // Only bars with room for the name get one. Most branches in a busy
            // repository last a day and are a few pixels wide; spilling their names into
            // the space beside them turns the whole chart into overlapping text.
            let label = Text(bar.branch.name)
                .font(.system(size: 9, weight: .medium))
            if bar.frame.width > 70 {
                context.draw(
                    label.foregroundStyle(heat > 0.45 ? Color.black.opacity(0.8) : Palette.primaryText),
                    in: bar.frame.insetBy(dx: 5, dy: 1)
                )
            } else if isSelected || isHovered, bar.frame.maxX + 6 < size.width {
                // The one bar the user is pointing at can afford to spill.
                context.draw(
                    label.foregroundStyle(Palette.primaryText),
                    at: CGPoint(x: bar.frame.maxX + 6, y: bar.frame.midY),
                    anchor: .leading
                )
            }
        }
    }

    private var axis: some View {
        HStack {
            Text(dateRange.lowerBound.formatted(date: .abbreviated, time: .omitted))
            Spacer()
            Text("\(branches.count.formatted()) merged branches · coloured by lines changed")
            Spacer()
            Text(dateRange.upperBound.formatted(date: .abbreviated, time: .omitted))
        }
        .font(.system(size: 10))
        .foregroundStyle(Palette.faintText)
        .padding(.horizontal, 14)
        .frame(height: Self.axisHeight)
        .frame(maxWidth: .infinity)
        .background(Palette.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private func tooltip(for branch: Branch, in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(branch.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.primaryText)
            Text("\(branch.commitCount.formatted()) commits · \(branch.churn.formatted()) lines · \(branch.days == 0 ? "same day" : "\(branch.days)d")")
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline))
        .fixedSize()
        .offset(
            x: min(pointer.x + 14, max(size.width - 280, 0)),
            y: min(pointer.y + 14, max(size.height - 60, 0))
        )
        .allowsHitTesting(false)
    }
}
