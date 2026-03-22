//
//  CouplingDetailView.swift
//  codewake
//
//  Created by Luis Resendez on 22/03/2026.
//

import CodewakeKit
import SwiftUI

/// Inspector for the coupling map: what each group of files is, and how much of the
/// history the answer rests on.
struct CouplingDetailView: View {
    let report: CouplingReport
    let selection: FileID?
    let onSelect: (FileID?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                ForEach(report.clusters) { cluster in
                    group(cluster)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280)
        .panelBackground()
        .overlay(alignment: .leading) { Rectangle().fill(Palette.hairline).frame(width: 1) }
    }

    private var summary: some View {
        InspectorSection("What this is") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(report.clusters.count)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.primaryText)
                    Text(report.clusters.count == 1 ? "group of files\nthat move together" : "groups of files\nthat move together")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("A line means the two files changed in the same commit most of the time one of them changed at all. Thicker is tighter.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if report.ignoredCommits > 0 {
                    Text("\(report.ignoredCommits.formatted()) of \(( report.ignoredCommits + report.consideredCommits).formatted()) commits touched too many files to count — a sweep couples everything to everything.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.faintText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func group(_ cluster: CouplingCluster) -> some View {
        InspectorSection("\(cluster.files.count) files · \(percent(cluster.strength)) at its tightest") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(cluster.files, id: \.self) { id in
                    Button { onSelect(id == selection ? nil : id) } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(id == selection ? Color.white : Palette.coupling)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(report.path(id).split(separator: "/").last ?? ""))
                                    .font(.system(size: 12, weight: id == selection ? .semibold : .regular))
                                    .foregroundStyle(Palette.primaryText)
                                Text(report.path(id).split(separator: "/").dropLast().joined(separator: "/"))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Palette.faintText)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer(minLength: 4)
                            Text("\((report.commitCounts[id] ?? 0).formatted())")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.faintText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
