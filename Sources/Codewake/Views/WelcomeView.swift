//
//  WelcomeView.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

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
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.accent)
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
