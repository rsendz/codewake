//
//  MainView.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CodewakerKit
import SwiftUI

struct MainView: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            switch state.phase {
            case .welcome:
                WelcomeView(recents: state.recentRepositories) { state.open($0) }
            case .loading(let message):
                loading(message)
            case .failed(let message):
                failure(message)
            case .ready:
                repository
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Palette.canvas)
        .preferredColorScheme(.dark)
        .task { state.openLaunchRepository() }
    }

    // MARK: - States

    private func loading(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(Palette.accent)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Choose Another Repository…") {
                chooseRepository { state.open($0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loaded repository

    private var repository: some View {
        VStack(spacing: 0) {
            statusBar
            Divider().overlay(Palette.hairline)

            HStack(spacing: 0) {
                TreemapView(
                    hotspots: state.hotspots,
                    selection: state.selection,
                    onSelect: { state.select($0) }
                )
                FileDetailView(
                    detail: state.detail,
                    hotspot: state.hotspots.first { $0.id == state.selection }
                )
            }

            if let summary = state.summary {
                TimelineView(
                    commits: summary.commits,
                    commitIndex: state.commitIndex,
                    isPlaying: state.isPlaying,
                    onScrub: { state.scrub(to: $0) },
                    onTogglePlayback: { state.togglePlayback() }
                )
            }
        }
        // Arrow keys step one commit at a time, for picking apart a moment the drag flew past.
        .focusable()
        .onKeyPress(.leftArrow) { state.step(by: -1); return .handled }
        .onKeyPress(.rightArrow) { state.step(by: 1); return .handled }
        .onKeyPress(.space) { state.togglePlayback(); return .handled }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Text(state.summary?.name ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.primaryText)

            if let statistics = state.statistics {
                stat("\(statistics.fileCount.formatted())", "files")
                stat("\(statistics.totalLines.formatted())", "lines")
            }
            if let commit = state.currentCommit {
                stat(commit.date.formatted(.dateTime.month(.abbreviated).year()), "")
            }

            Spacer()

            if state.isRefining {
                ProgressView()
                    .controlSize(.mini)
                    .help("Measuring complexity")
            }
            Button("Open…") { chooseRepository { state.open($0) } }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .panelBackground()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.primaryText)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.faintText)
            }
        }
    }
}

/// A fresh `AppState` has no repository open, so this is the welcome screen rather than a
/// map. The maps are driven by parsed git history, which a preview has no way to supply.
#Preview("Main window") {
    MainView(state: AppState())
        .frame(width: 1240, height: 820)
}
