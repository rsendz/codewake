//
//  BranchDetailView.swift
//  codewake
//
//  Created by Luis Resendez on 28/02/2026.
//

import CodewakeKit
import SwiftUI

/// Inspector for a selected branch.
struct BranchDetailView: View {
    let branch: Branch?
    let totalBranches: Int
    let mergeCount: Int

    var body: some View {
        ScrollView {
            if let branch {
                content(branch)
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
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 22))
                .foregroundStyle(Palette.faintText)
            Text("Select a branch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("Each bar is a line of work, from its first commit to the day it merged. Selecting one moves the timeline to where it landed.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faintText)
                .multilineTextAlignment(.center)

            if totalBranches > 0 {
                Text("\(totalBranches.formatted()) branches reconstructed from \(mergeCount.formatted()) merge commits")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.faintText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        }
        .padding(24)
        .padding(.top, 50)
    }

    private func content(_ branch: Branch) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(branch.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .textSelection(.enabled)
                Text("merged \(branch.mergeDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.faintText)
            }

            InspectorSection("Size of the change") {
                VStack(spacing: 5) {
                    InspectorRow("Commits", branch.commitCount.formatted())
                    InspectorRow("Lines changed", branch.churn.formatted())
                    InspectorRow("File edits", branch.filesTouched.formatted())
                }
            }

            InspectorSection("In flight") {
                VStack(spacing: 5) {
                    InspectorRow("Opened", branch.startDate.formatted(date: .abbreviated, time: .omitted))
                    InspectorRow("Merged", branch.mergeDate.formatted(date: .abbreviated, time: .omitted))
                    InspectorRow("Lifespan", branch.days == 0 ? "same day" : "\(branch.days) days")
                }
            }

            if !branch.authors.isEmpty {
                InspectorSection("Who worked on it") {
                    VStack(spacing: 5) {
                        ForEach(branch.authors.prefix(5)) { author in
                            InspectorRow(author.name, "\(author.commits)")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared inspector chrome, so the file and branch panels read as one design.
struct InspectorSection<Content: View>: View {
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

struct InspectorRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.primaryText)
        }
    }
}
