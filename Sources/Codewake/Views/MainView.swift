//
//  MainView.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CodewakeKit
import SwiftUI

struct MainView: View {
    @Bindable var state: AppState
    @FocusState private var isSearchFocused: Bool

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
        .frame(minWidth: 960, minHeight: 640)
        .background(Palette.canvas)
        .preferredColorScheme(.dark)
        .navigationTitle(state.summary?.name ?? "Codewake")
        .task { state.openLaunchRepository() }
        .sheet(isPresented: $state.isShowingHelp) { HelpView() }
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
                switch state.viewMode {
                case .map:
                    VStack(spacing: 0) {
                        TreemapView(
                            hotspots: state.hotspots,
                            selection: state.selection,
                            coupled: state.coupledFiles,
                            searchMatches: state.searchMatches,
                            onSelect: { state.select($0) }
                        )
                        mapFooter
                    }
                    FileDetailView(
                        detail: state.detail,
                        hotspot: state.hotspots.first { $0.id == state.selection },
                        onSelectFile: { state.select($0) },
                        onReveal: { state.revealSelectionInFinder() },
                        onCopyPath: { state.copySelectionPath() }
                    )
                case .ownership:
                    let report = state.ownership ?? .empty
                    let colors = AuthorColors(report)
                    VStack(spacing: 0) {
                        OwnershipView(
                            report: report,
                            colors: colors,
                            isLoading: state.ownership == nil,
                            selection: state.selection,
                            highlightedAuthor: state.highlightedAuthor,
                            onSelect: { state.select($0) }
                        )
                        ownershipFooter(report)
                    }
                    OwnershipDetailView(
                        report: report,
                        colors: colors,
                        detail: state.detail,
                        highlightedAuthor: state.highlightedAuthor,
                        onHighlight: { state.highlightedAuthor = $0 }
                    )
                case .branches:
                    BranchesView(
                        branches: state.summary?.branches ?? [],
                        dateRange: state.summary?.dateRange ?? Date()...Date(),
                        selection: state.selectedBranch,
                        playheadDate: state.currentCommit?.date,
                        onSelect: { state.select(branch: $0) }
                    )
                    BranchDetailView(
                        branch: state.branch,
                        totalBranches: state.summary?.branches.count ?? 0,
                        mergeCount: state.summary?.mergeCount ?? 0
                    )
                }
            }

            if let summary = state.summary {
                TimelineView(
                    commits: summary.commits,
                    commitIndex: state.commitIndex,
                    isPlaying: state.isPlaying,
                    speed: $state.playbackSpeed,
                    onScrub: { state.scrub(to: $0) },
                    onTogglePlayback: { state.togglePlayback() }
                )
            }
        }
        // Arrow keys step one commit at a time, for picking apart a moment the drag flew past.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { state.step(by: -1); return .handled }
        .onKeyPress(.rightArrow) { state.step(by: 1); return .handled }
        .onKeyPress(.space) { state.togglePlayback(); return .handled }
        .onKeyPress(.escape) {
            state.clearFocus()
            return .handled
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Text(state.summary?.name ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.primaryText)

            Picker("", selection: $state.viewMode) {
                ForEach(AppState.ViewMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if state.viewMode.showsFiles, let statistics = state.statistics {
                stat("\(statistics.fileCount.formatted())", "files")
                stat("\(statistics.totalLines.formatted())", "lines")
            }
            if let commit = state.currentCommit {
                stat(commit.date.formatted(.dateTime.month(.abbreviated).year()), "")
            }

            Spacer()

            if state.isRefining || state.isComputingOwnership {
                ProgressView()
                    .controlSize(.mini)
                    .help("Measuring complexity")
            }
            if state.viewMode == .map { searchField }

            Button { state.isShowingHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.secondaryText)
            .help("What do these terms mean?")

            Button("Open…") { chooseRepository { state.open($0) } }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .panelBackground()
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faintText)
            TextField("Filter files", text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 130)
                .focused($isSearchFocused)
            if !state.searchText.isEmpty {
                Button { state.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.faintText)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)))
        .onKeyPress(.escape) {
            state.searchText = ""
            isSearchFocused = false
            return .handled
        }
        .onChange(of: state.focusSearchToken) { isSearchFocused = true }
    }

    /// What a colour means on the ownership map, in the same place the heat scale sits on
    /// the hotspot map.
    private func ownershipFooter(_ report: OwnershipReport) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(Array(report.authors.prefix(Palette.authorSlotCount).enumerated()), id: \.offset) { index, _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.author(index))
                        .frame(width: 9, height: 9)
                }
                Text("colour is the author with the most commits to a file")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.faintText)
                    .padding(.leading, 2)
            }

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.author(nil, strength: 0))
                    .frame(width: 9, height: 9)
                Text("no clear owner")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.faintText)
            }

            Spacer()

            if report.files.count > OwnershipView.tileLimit {
                Text("showing the \(OwnershipView.tileLimit) largest of \(report.totalFiles.formatted()) files")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.faintText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Palette.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    /// The colour scale, always on screen. The map is unreadable without knowing which end
    /// is bad, and sending people to a help sheet for that is a poor trade.
    private var mapFooter: some View {
        HStack(spacing: 12) {
            LegendStrip()
            Spacer()
            if state.selection != nil, !state.coupledFiles.isEmpty {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Palette.coupling, lineWidth: 1.5)
                        .frame(width: 11, height: 9)
                    Text("changes with the selected file")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.faintText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Palette.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
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
