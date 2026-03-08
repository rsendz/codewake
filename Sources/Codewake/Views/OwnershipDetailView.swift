//
//  OwnershipDetailView.swift
//  codewake
//
//  Created by Luis Resendez on 08/03/2026.
//

import CodewakeKit
import SwiftUI

/// Inspector for the ownership map: how concentrated knowledge of this codebase is, and
/// in whom.
struct OwnershipDetailView: View {
    let report: OwnershipReport
    let colors: AuthorColors
    /// Author breakdown for whichever file is selected, if any.
    let detail: FileDetail?
    let highlightedAuthor: String?
    let onHighlight: (String?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let file = selectedFile { selection(file) }
                risk
                authors
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280)
        .panelBackground()
        .overlay(alignment: .leading) { Rectangle().fill(Palette.hairline).frame(width: 1) }
    }

    private var selectedFile: FileOwnership? {
        detail.flatMap { report.ownership(of: $0.snapshot.id) }
    }

    // MARK: - Selected file

    private func selection(_ file: FileOwnership) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path.split(separator: "/").last.map(String.init) ?? file.path)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(file.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.faintText)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.color(for: file.owner))
                    .frame(width: 8, height: 8)
                Text(file.isSoleAuthored
                     ? "\(file.owner) is the only author"
                     : "\(file.owner) owns \(percent(file.share)) of \(file.commits.formatted()) commits")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let authors = detail?.authors, authors.count > 1 {
                let total = max(authors.reduce(0) { $0 + $1.commits }, 1)
                InspectorSection("Commits by author") {
                    VStack(spacing: 5) {
                        ForEach(authors.prefix(6)) { author in
                            InspectorRow(author.name, percent(Double(author.commits) / Double(total)))
                        }
                    }
                }
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Repository-wide

    private var risk: some View {
        InspectorSection("Knowledge risk") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(report.busFactor.formatted())
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.primaryText)
                    Text(report.busFactor == 1
                         ? "person owns half\nthe code"
                         : "people own half\nthe code")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Palette.accent)
                                .frame(width: max(2, proxy.size.width * report.soleAuthoredLineShare))
                        }
                    }
                    .frame(height: 6)
                    Text("\(percent(report.soleAuthoredLineShare)) of the code — \(report.soleAuthoredFiles.formatted()) of \(report.totalFiles.formatted()) files — has only ever been touched by one person.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.faintText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var authors: some View {
        InspectorSection("Who owns what") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(report.authors.prefix(12)) { author in
                    row(author)
                }
                if report.authors.count > 12 {
                    Text("and \((report.authors.count - 12).formatted()) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.faintText)
                        .padding(.top, 3)
                }
                Text("Click a name to light up only their files.")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.faintText)
                    .padding(.top, 5)
            }
        }
    }

    private func row(_ author: AuthorOwnership) -> some View {
        let isHighlighted = author.name == highlightedAuthor
        let share = report.totalLines > 0
            ? Double(author.ownedLines) / Double(report.totalLines)
            : 0

        return Button {
            onHighlight(isHighlighted ? nil : author.name)
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.color(for: author.name))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(author.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                    Text("\(author.ownedFiles.formatted()) \(author.ownedFiles == 1 ? "file" : "files") · \(author.soleAuthoredFiles.formatted()) alone")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.faintText)
                }
                Spacer(minLength: 4)
                Text(percent(share))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.primaryText)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHighlighted ? Color.white.opacity(0.09) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(author.name) — owns \(author.ownedFiles.formatted()) files, \(author.soleAuthoredFiles.formatted()) of which nobody else has touched, and has edited \(author.touchedFiles.formatted()) in all")
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
