//
//  WelcomeView.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CodewakeKit
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    let recents: [URL]
    let onOpen: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            masthead
            Spacer().frame(height: 28)

            Button("Open Repository…") { chooseRepository(onOpen: onOpen) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            if !recents.isEmpty {
                recentList
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(10)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in onOpen(url) }
            }
            return true
        }
    }

    private var masthead: some View {
        VStack(spacing: 14) {
            MapAnimation()
                .frame(width: 148, height: 92)
            Text("Codewake")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text("Scrub through a repository's history and watch its hotspots move.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("RECENT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.faintText)
                .padding(.bottom, 3)

            ForEach(recents, id: \.self) { url in
                Button { onOpen(url) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.faintText)
                        Text(url.lastPathComponent)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.primaryText)
                        Text(url.deletingLastPathComponent().path)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.faintText)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 380, alignment: .leading)
        .padding(.top, 34)
    }
}

/// A small map building itself and heating up, on a loop.
///
/// Drawn with the same squarified layout and the same heat ramp the real map uses, over
/// invented files, so the thing on the welcome screen cannot drift from the thing the app
/// does. It is decoration and nothing else: no hit testing, nothing behind it to click, and
/// it goes away with the rest of this screen the moment a repository opens.
private struct MapAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// Sizes chosen to squarify into a recognisable map rather than a grid.
    private static let areas: [Double] = [34, 21, 18, 13, 11, 9, 8, 6, 5, 4, 3, 2]
    /// How long the map takes to build itself, once, and how long a sweep of heat takes.
    private static let build: Double = 1.9
    private static let sweep: Double = 6

    var body: some View {
        if reduceMotion {
            Canvas { context, size in draw(elapsed: Self.build + 1.4, in: &context, size: size) }
        } else {
            SwiftUI.TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                Canvas { context, size in draw(elapsed: elapsed, in: &context, size: size) }
            }
        }
    }

    private func draw(elapsed: Double, in context: inout GraphicsContext, size: CGSize) {
        let frames = TreemapLayout.squarify(
            Self.areas, in: CGRect(origin: .zero, size: size)
        )

        for (index, frame) in frames.enumerated() {
            let tile = Double(index) / Double(Self.areas.count)

            // Files arrive once, largest first, the way history fills a repository in. This
            // does not loop: a map that emptied itself every few seconds would read as the
            // repository being deleted, and would leave the masthead blank a fifth of the
            // time.
            let arrival = eased(min(max((elapsed - tile * Self.build * 0.8) / 0.5, 0), 1))
            guard arrival > 0.01 else { continue }

            // Heat sweeps across them for as long as the screen is up, which is what
            // scrubbing through a repository's history looks like. It never falls to
            // nothing: a tile that vanished when it cooled would read as a file being
            // deleted rather than as a file being calm.
            let phase = elapsed / Self.sweep - tile * 0.55
            let wave = max(sin(phase * 2 * .pi), 0)
            let heat = (0.14 + 0.86 * wave) * arrival

            let inset = frame.insetBy(dx: 1.5, dy: 1.5)
            guard inset.width > 0.5, inset.height > 0.5 else { continue }
            let shrink: CGFloat = CGFloat(1 - arrival) / 2
            let grown = inset.insetBy(dx: inset.width * shrink, dy: inset.height * shrink)
            let opacity: Double = 0.45 + 0.55 * arrival
            let fill: Color = Palette.hotspot(heat).opacity(opacity)
            context.fill(Path(roundedRect: grown, cornerRadius: 2), with: .color(fill))
        }
    }

    /// Smoothstep, so tiles arrive without the corner a linear ramp puts on the motion.
    private func eased(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

/// Shared by the welcome screen and the ⌘O menu item.
@MainActor
func chooseRepository(onOpen: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    panel.message = "Choose a Git repository"
    if panel.runModal() == .OK, let url = panel.url {
        onOpen(url)
    }
}

#Preview("Welcome") {
    WelcomeView(recents: [
        URL(filePath: "/Users/luis/Code/codewake"),
        URL(filePath: "/Users/luis/Code/swift-nio"),
    ]) { _ in }
    .frame(width: 760, height: 520)
}
