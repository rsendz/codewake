//
//  FileDetailView.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CodewakerKit
import SwiftUI

/// Inspector for the selected file: what it is now, and how it got that way.
struct FileDetailView: View {
    let detail: FileDetail?
    let hotspot: Hotspot?

    var body: some View {
        ScrollView {
            if let detail {
                content(detail)
            } else {
                placeholder
            }
        }
        .frame(width: 280)
        .panelBackground()
        .overlay(alignment: .leading) { Rectangle().fill(Palette.hairline).frame(width: 1) }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 22))
                .foregroundStyle(Palette.faintText)
            Text("Select a file")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("Click any rectangle to see its history at this point in time.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faintText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func content(_ detail: FileDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(detail)
            if let hotspot { risk(hotspot) }
            measures(detail)
            if !detail.churnHistory.isEmpty { churn(detail) }
            if !detail.authors.isEmpty { authors(detail) }
            if !detail.recentCommits.isEmpty { commits(detail) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ detail: FileDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(detail.snapshot.path.split(separator: "/").last.map(String.init) ?? "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text(detail.snapshot.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.faintText)
                .textSelection(.enabled)
            if detail.wasRenamed {
                Label("moved during its life", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func risk(_ hotspot: Hotspot) -> some View {
        Section("Hotspot score") {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Palette.hotspot(hotspot.score))
                            .frame(width: max(4, proxy.size.width * hotspot.score))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("churn \(percent(hotspot.normalizedChurn))")
                    Text("·")
                    Text("complexity \(percent(hotspot.normalizedComplexity))")
                    if hotspot.isEstimated {
                        Text("· estimated")
                            .foregroundStyle(Palette.accent.opacity(0.8))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.faintText)
            }
        }
    }

    private func measures(_ detail: FileDetail) -> some View {
        Section("At this commit") {
            VStack(spacing: 5) {
                measure("Lines", detail.snapshot.approximateLines.formatted())
                measure("Commits", detail.snapshot.commitCount.formatted())
                measure("Lines churned", detail.snapshot.churn.formatted())
                if let complexity = detail.complexity {
                    measure("Deepest nesting", complexity.max.formatted())
                    measure("Mean nesting", complexity.mean.formatted(.number.precision(.fractionLength(1))))
                }
            }
        }
    }

    private func measure(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.primaryText)
        }
    }

    /// Churn per commit over the file's life — the shape that shows whether a file is
    /// settling down or still being fought over.
    private func churn(_ detail: FileDetail) -> some View {
        Section("Churn over time") {
            let peak = Double(detail.churnHistory.map(\.churn).max() ?? 1)
            Canvas { context, size in
                let count = detail.churnHistory.count
                let step = count > 1 ? size.width / CGFloat(count - 1) : size.width
                let barWidth = max(1, min(4, step - 1))

                for (index, point) in detail.churnHistory.enumerated() {
                    let magnitude = peak > 0 ? log1p(Double(point.churn)) / log1p(peak) : 0
                    let height = max(1, CGFloat(magnitude) * size.height)
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(index) * step, y: size.height - height,
                            width: barWidth, height: height
                        )),
                        with: .color(Palette.accent.opacity(0.75))
                    )
                }
            }
            .frame(height: 38)
        }
    }

    private func authors(_ detail: FileDetail) -> some View {
        let total = max(detail.authors.reduce(0) { $0 + $1.commits }, 1)
        return Section("Who touched it") {
            VStack(spacing: 5) {
                ForEach(detail.authors.prefix(5)) { author in
                    HStack(spacing: 6) {
                        Text(author.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int((Double(author.commits) / Double(total) * 100).rounded()))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.faintText)
                    }
                }
            }
        }
    }

    private func commits(_ detail: FileDetail) -> some View {
        Section("Recent commits") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(detail.recentCommits) { commit in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(commit.subject)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(2)
                        Text("\(commit.authorName) · \(commit.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.faintText)
                    }
                }
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Small labelled block, so every section in the inspector reads the same way.
    private struct Section<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.faintText)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
