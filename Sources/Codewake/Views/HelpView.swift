//
//  HelpView.swift
//  codewake
//
//  Created by Luis Resendez on 28/02/2026.
//

import SwiftUI

/// Explains what the app measures and what the words mean.
///
/// Every term here is jargon borrowed from a fairly niche corner of software analysis. A
/// map coloured by "churn x complexity" is meaningless to someone seeing those words for
/// the first time, so the glossary is part of the product rather than a footnote in a
/// README nobody opens.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    whatItDoes
                    glossary
                    reading
                    shortcuts
                    caveats
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620, height: 620)
        .background(Palette.panel)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text("How to read Codewake")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var whatItDoes: some View {
        Section("What this tool is for") {
            Paragraph("""
                Codewake replays your repository's history. The map shows the codebase as it \
                existed at whatever moment the playhead is pointing at, and dragging the \
                timeline moves through time.

                It is built to answer a question `git log` cannot: **which parts of this \
                codebase are risky to touch, and how did they get that way?**
                """)
        }
    }

    private var glossary: some View {
        Section("The words on screen") {
            VStack(alignment: .leading, spacing: 14) {
                Term(
                    "Churn",
                    "How many lines have been added and deleted in a file over its life. High churn means the file keeps being rewritten. It is a measure of activity, not of quality — a file can churn because it is central and important, or because it is never quite right."
                )
                Term(
                    "Complexity",
                    "Estimated from how deeply the code is indented. Deeply nested code is code full of conditions and loops inside other conditions and loops, which is harder to hold in your head. This is an approximation, not a parse: it works on any language, but it cannot tell a nested loop from a nested data structure."
                )
                Term(
                    "Hotspot",
                    "A file that is high in **both** churn and complexity. Neither alone is a problem — complicated code nobody touches is dormant, and a simple file edited constantly is usually fine. It is the combination that predicts where bugs and slow work come from, because it means people keep having to change something that is hard to change safely."
                )
                Term(
                    "Change coupling",
                    "Two files are coupled when they keep being edited in the same commit. It often reveals a dependency the code does not state anywhere — if you always have to edit the parser whenever you edit the model, those two are joined whether or not either imports the other. Select a file to see its partners outlined on the map."
                )
                Term(
                    "Branch",
                    "A line of work developed away from the main line and merged back. The Branches view reconstructs them from merge commits: when each one started, how long it ran, and how much it changed."
                )
            }
        }
    }

    private var reading: some View {
        Section("Reading the map") {
            VStack(alignment: .leading, spacing: 12) {
                Bullet("Each rectangle is a file. **Bigger means longer** — more lines of code.")
                Bullet("**Colour is the hotspot score.** Cool blue is calm; orange and red are files that are both large or tangled and frequently changed.")
                Bullet("Files are **grouped by top-level folder**, so the shape stays recognisable as you scrub.")
                Bullet("Colour is relative to the hottest file currently on screen, so early history still has contrast to read rather than being uniformly cold.")

                LegendStrip()
                    .padding(.top, 4)
            }
        }
    }

    private var shortcuts: some View {
        Section("Shortcuts") {
            VStack(alignment: .leading, spacing: 7) {
                Shortcut("Drag the timeline", "Move through history")
                Shortcut("← →", "Step one commit")
                Shortcut("Space", "Play or pause")
                Shortcut("⌘ ⌥ ←  /  ⌘ ⌥ →", "Jump to the first or last commit")
                Shortcut("⌘F", "Search files — matches stay lit, the rest dim")
                Shortcut("Esc", "Clear the selection or the search")
                Shortcut("⌘O", "Open another repository")
            }
        }
    }

    private var caveats: some View {
        Section("What it does not do") {
            VStack(alignment: .leading, spacing: 12) {
                Bullet("Generated and vendored files — lock files, `node_modules`, build output — are **excluded**. They churn enormously and would take the top spot in every repository while telling you nothing.")
                Bullet("Merge commits are skipped when counting churn, so work is not counted twice.")
                Bullet("Only the current branch's history is read. Branches that were never merged do not appear.")
                Bullet("A hotspot is a **question, not a verdict**. It tells you where to look, not what is wrong.")
            }
        }
    }

    // MARK: - Building blocks

    private struct Section<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.accent)
                content
            }
        }
    }

    private struct Term: View {
        let name: String
        let explanation: String

        init(_ name: String, _ explanation: String) {
            self.name = name
            self.explanation = explanation
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Paragraph(explanation)
            }
        }
    }

    private struct Bullet: View {
        let text: String
        init(_ text: String) { self.text = text }

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Palette.faintText)
                    .frame(width: 3, height: 3)
                    .padding(.top, 6)
                Paragraph(text)
            }
        }
    }

    private struct Shortcut: View {
        let keys: String
        let meaning: String
        init(_ keys: String, _ meaning: String) {
            self.keys = keys
            self.meaning = meaning
        }

        var body: some View {
            HStack(spacing: 12) {
                Text(keys)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.primaryText)
                    .frame(width: 132, alignment: .leading)
                Text(meaning)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
            }
        }
    }

    private struct Paragraph: View {
        let text: String
        init(_ text: String) { self.text = text }

        var body: some View {
            // Markdown so **emphasis** in the copy renders without a second styling system.
            Text(.init(text))
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The colour ramp with its ends labelled — shown in help and under the map, because a
/// colour scale nobody can decode is just decoration.
struct LegendStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 0.05).map { Palette.hotspot($0) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 7)
            .clipShape(Capsule())

            HStack {
                Text("calm")
                Spacer()
                Text("churns, and complex enough that changing it is risky")
                Spacer()
                Text("hotspot")
            }
            .font(.system(size: 9))
            .foregroundStyle(Palette.faintText)
        }
        .frame(maxWidth: 460)
    }
}

#Preview("Help") {
    HelpView()
}
