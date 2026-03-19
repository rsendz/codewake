//
//  AgeDetailView.swift
//  codewake
//
//  Created by Luis Resendez on 19/03/2026.
//

import CodewakeKit
import SwiftUI

/// Inspector for the age map: how much of this codebase has stopped moving, and where.
struct AgeDetailView: View {
    let report: AgeReport
    let detail: FileDetail?
    let onOpen: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let file = selectedFile { selection(file) }
                dormancy
                directories
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280)
        .panelBackground()
        .overlay(alignment: .leading) { Rectangle().fill(Palette.hairline).frame(width: 1) }
    }

    private var selectedFile: FileAge? {
        detail.flatMap { report.age(of: $0.snapshot.id) }
    }

    private func selection(_ file: FileAge) -> some View {
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
                    .fill(Palette.age(file.share))
                    .frame(width: 8, height: 8)
                Text("Last touched \(Age.phrase(file.age))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.primaryText)
            }

            InspectorSection("At this commit") {
                InspectorRow("Lines", file.lines.formatted())
                InspectorRow("Last change", file.lastTouched.formatted(.dateTime.day().month(.abbreviated).year()))
            }
        }
    }

    /// The headline. A quarter of a codebase nobody has opened in a year is not a problem
    /// by itself — but it is the first thing worth knowing about the shape of the map.
    private var dormancy: some View {
        InspectorSection("Still moving") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Age.span(report.medianAge))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.primaryText)
                    Text("since the median file\nwas last touched")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if report.totalLines > 0 {
                    let share = Double(report.dormantLines) / Double(report.totalLines)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Palette.age(0.85))
                                .frame(width: max(proxy.size.width * share, share > 0 ? 3 : 0))
                        }
                    }
                    .frame(height: 5)

                    Text("\(percent(share)) of the code — \(report.dormantFiles.formatted()) of \(report.files.count.formatted()) files — has not been touched in a year.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var directories: some View {
        InspectorSection("Oldest corners") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(report.directories.prefix(8)) { directory in
                    Button { onOpen(directory.name) } label: {
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Palette.age(min(directory.medianAge / report.span, 1)))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(directory.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.primaryText)
                                Text("\(directory.files.formatted()) files · \(directory.lines.formatted()) lines")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.faintText)
                            }
                            Spacer(minLength: 6)
                            Text(Age.span(directory.medianAge))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(directory.name == "/")
                }

                Text("By the median age of the files in each, oldest first. Click one to open it.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.faintText)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
