//
//  AppState.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import AppKit
import CodewakeKit
import Foundation
import SwiftUI

/// Drives the whole app: owns the engine, the scrub position, and what the views show.
///
/// Scrubbing runs on two tracks. Every position change immediately asks the engine for a
/// result built from cached complexity, which never suspends on git and so keeps up with
/// the drag. Once the playhead has been still for a moment, a second pass reads whatever
/// blobs are missing and replaces the estimate. Both paths tag results with the position
/// they describe, so a slow refine landing late is discarded rather than shown.
@MainActor
@Observable
final class AppState {
    enum Phase {
        case welcome
        case loading(String)
        case ready
        case failed(String)
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case map = "Map"
        case ownership = "Ownership"
        case age = "Age"
        case coupling = "Coupling"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .map: "square.grid.2x2"
            case .ownership: "person.2"
            case .age: "clock.arrow.circlepath"
            case .coupling: "point.3.connected.trianglepath.dotted"
            }
        }
    }

    private(set) var phase: Phase = .welcome
    private(set) var summary: RepositorySummary?
    private(set) var hotspots: [Hotspot] = []
    private(set) var statistics: SnapshotStatistics?
    private(set) var isRefining = false
    private(set) var isComputingDerived = false
    private(set) var ownership: OwnershipReport?
    private(set) var ages: AgeReport?
    private(set) var coupling: CouplingReport?
    /// Author-to-colour assignment, fixed for the life of the loaded repository so a person
    /// keeps their colour however far the playhead moves.
    private(set) var authorColors = AuthorColors(ranking: [])
    private(set) var repositoryURL: URL?

    var commitIndex: Int = 0
    private(set) var selection: FileID?
    private(set) var detail: FileDetail?
    private(set) var isPlaying = false

    var viewMode: ViewMode = .map {
        didSet { refreshDerivedView() }
    }
    /// When set, the ownership map dims everything this author does not own.
    var highlightedAuthor: String?
    /// Directory the map is opened into, as path components; empty is the whole repository.
    ///
    /// At repository scale the smallest files are a few points across — visible, but with no
    /// room for a name. Opening a directory hands its files the whole canvas, which is the
    /// level at which they can be read and worked with.
    private(set) var mapRoot: [String] = []
    var searchText: String = ""
    var isShowingHelp = false
    /// Bumped to ask the search field to take focus. A plain Bool would not re-fire when
    /// the shortcut is pressed twice in a row.
    private(set) var focusSearchToken = 0
    /// Multiplier on playback speed. At 1x the whole history plays in about 30 seconds.
    var playbackSpeed: Double = 1

    private var engine: AnalysisEngine?
    private var refineTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var derivedTask: Task<Void, Never>?
    /// Only the newest derived-view task may clear `isComputingDerived`. Cancelling a
    /// task does not run its `defer` synchronously — it fires whenever that task next gets
    /// scheduled, which is after the replacement has already set the flag.
    private var derivedGeneration = 0
    private var playbackTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    /// How long the playhead must sit still before spending git reads on exact complexity.
    private let refineDelay = Duration.milliseconds(180)
    /// The equivalent wait for views computed from history already in memory. Much shorter,
    /// because there is no git read to avoid — just enough to coalesce a fast drag.
    private let derivedDelay = Duration.milliseconds(30)

    // MARK: - Repository lifecycle

    var recentRepositories: [URL] {
        (UserDefaults.standard.array(forKey: "recentRepositories") as? [String] ?? [])
            .map { URL(filePath: $0) }
    }

    func open(_ url: URL) {
        loadTask?.cancel()
        stopPlayback()
        phase = .loading("Reading history…")

        loadTask = Task {
            do {
                let engine = try await AnalysisEngine.load(from: GitCLIHistoryProvider(repositoryURL: url)) { phase in
                    Task { @MainActor [weak self] in
                        self?.report(phase)
                    }
                }
                guard !Task.isCancelled else { return }

                self.engine = engine
                self.summary = engine.summary
                self.authorColors = AuthorColors(ranking: engine.summary.authorRanking)
                self.repositoryURL = url
                self.commitIndex = engine.summary.commitCount - 1
                self.selection = nil
                self.mapRoot = []
                self.searchText = ""
                self.detail = nil
                self.ownership = nil
                self.ages = nil
                self.coupling = nil
                self.highlightedAuthor = nil
                self.phase = .ready
                self.rememberRecent(url)
                self.scrub(to: self.commitIndex, refine: true)
            } catch is CancellationError {
                return
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Opens a repository chosen at launch, so a demo or a debugging run can skip the file
    /// picker:
    ///
    ///     CODEWAKE_REPO=~/some/repo swift run codewake
    ///     swift run codewake -repo ~/some/repo
    ///
    /// Deliberately not a bare positional path: AppKit reads an argument like that as a
    /// request to open a document, and SwiftUI then withholds the `WindowGroup` window
    /// waiting for a document scene that never arrives — the app runs with no window at
    /// all. A `-flag` argument goes to the user defaults argument domain instead, which is
    /// harmless, so `-repo` is read straight back out of `UserDefaults`.
    func openLaunchRepository() {
        let flag = UserDefaults.standard.string(forKey: "repo")
        let environment = ProcessInfo.processInfo.environment["CODEWAKE_REPO"]
        guard let path = flag ?? environment, !path.isEmpty else { return }
        open(URL(filePath: NSString(string: path).expandingTildeInPath))
    }

    func closeRepository() {
        loadTask?.cancel()
        stopPlayback()
        refineTask?.cancel()
        derivedTask?.cancel()
        engine = nil
        summary = nil
        authorColors = AuthorColors(ranking: [])
        repositoryURL = nil
        hotspots = []
        statistics = nil
        selection = nil
        mapRoot = []
        detail = nil
        ownership = nil
        ages = nil
        coupling = nil
        highlightedAuthor = nil
        searchText = ""
        phase = .welcome
    }

    private func report(_ loadPhase: LoadPhase) {
        switch loadPhase {
        case .readingHistory: phase = .loading("Reading history…")
        case .buildingTimelines: phase = .loading("Building timelines…")
        case .ready: break
        }
    }

    private func rememberRecent(_ url: URL) {
        var paths = recentRepositories.map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(8)), forKey: "recentRepositories")
    }

    // MARK: - Scrubbing

    func scrub(to index: Int, refine: Bool = true) {
        guard let engine, let summary else { return }
        let target = min(max(index, 0), summary.commitCount - 1)
        commitIndex = target

        refineTask?.cancel()
        refineTask = Task {
            // Fast pass first: whatever is already cached, with no chance of suspending on
            // git, so the view keeps up with the pointer.
            let immediate = await engine.scrub(to: target)
            guard !Task.isCancelled, immediate.commitIndex == self.commitIndex else { return }
            apply(immediate)

            guard refine, immediate.isEstimated else { return }
            isRefining = true
            defer { isRefining = false }

            try? await Task.sleep(for: refineDelay)
            guard !Task.isCancelled else { return }

            if let refined = try? await engine.refine(at: target),
               !Task.isCancelled, refined.commitIndex == self.commitIndex {
                apply(refined)
            }
        }
    }

    private func apply(_ result: AnalysisEngine.ScrubResult) {
        hotspots = result.hotspots
        statistics = result.statistics
        refreshDetail()
        refreshDerivedView()
    }

    /// Recomputes whichever view is on screen and is derived from the whole snapshot rather
    /// than from the top few hundred files.
    ///
    /// These walk every live file, so they are not free the way the hotspot map is — but
    /// they are cheap enough to keep up: ownership costs 1ms on a small repository and 16ms
    /// on git's own history. They were previously debounced by the same 180ms the
    /// complexity path uses, which is there to avoid *git reads*; nothing here touches git.
    /// Playback steps every 50ms, so that debounce meant the pending recompute was always
    /// cancelled before it fired and these views simply froze while the timeline played.
    private func refreshDerivedView() {
        derivedTask?.cancel()
        derivedGeneration += 1
        let generation = derivedGeneration

        guard let engine, viewMode != .map else {
            isComputingDerived = false
            return
        }
        let index = commitIndex
        let mode = viewMode
        isComputingDerived = true

        derivedTask = Task {
            defer { if generation == self.derivedGeneration { isComputingDerived = false } }
            // Playback is already rate-limited to 20 steps a second, so waiting again just
            // means never arriving.
            if !isPlaying {
                try? await Task.sleep(for: derivedDelay)
                guard !Task.isCancelled else { return }
            }

            switch mode {
            case .ownership:
                let report = await engine.ownership(at: index)
                guard !Task.isCancelled, index == self.commitIndex else { return }
                self.ownership = report
            case .age:
                let report = await engine.ages(at: index)
                guard !Task.isCancelled, index == self.commitIndex else { return }
                self.ages = report
            case .coupling:
                let report = await engine.couplingClusters(at: index)
                guard !Task.isCancelled, index == self.commitIndex else { return }
                self.coupling = report
            case .map:
                break
            }
        }
    }

    // MARK: - Opening a directory

    func open(directory name: String) {
        mapRoot.append(name)
        // A directory with exactly one subdirectory in it and nothing else is not a level
        // worth stopping at — opening `web` to find only `src` wastes the click and
        // the canvas. Keep descending until there is actually a choice to make.
        while let only = onlySubdirectory() {
            mapRoot.append(only)
        }
    }

    /// The single subdirectory of the current root, when it is the only thing there.
    private func onlySubdirectory() -> String? {
        let depth = mapRoot.count
        var names: Set<String> = []
        for hotspot in visibleHotspots {
            let components = hotspot.path.split(separator: "/")
            // A file sitting loose at this level means the level has content of its own.
            guard components.count > depth + 1 else { return nil }
            names.insert(String(components[depth]))
            if names.count > 1 { return nil }
        }
        return names.count == 1 ? names.first : nil
    }

    /// Back to `depth` components deep; 0 is the whole repository.
    func closeDirectory(to depth: Int) {
        mapRoot = Array(mapRoot.prefix(depth))
    }

    /// Path prefix every visible file shares, with its trailing slash.
    var rootPrefix: String {
        mapRoot.isEmpty ? "" : mapRoot.joined(separator: "/") + "/"
    }

    /// The files the map is currently showing. Colour, ranking and the treemap's own scale
    /// all work from this rather than from the whole repository, so opening a directory
    /// re-reads its contents against each other instead of against the codebase.
    var visibleHotspots: [Hotspot] {
        guard !mapRoot.isEmpty else { return hotspots }
        let prefix = rootPrefix
        return hotspots.filter { $0.path.hasPrefix(prefix) }
    }

    func isVisible(_ path: String) -> Bool {
        mapRoot.isEmpty || path.hasPrefix(rootPrefix)
    }

    func step(by delta: Int) {
        scrub(to: commitIndex + delta)
    }

    func focusSearch() {
        viewMode = .map
        focusSearchToken += 1
    }

    func jumpToStart() { scrub(to: 0) }

    func jumpToEnd() {
        guard let summary else { return }
        scrub(to: summary.commitCount - 1)
    }

    // MARK: - Playback

    /// Steps per second. Fixed, so playback stays smooth; speed changes how many commits
    /// each step advances instead.
    private static let stepsPerSecond = 20.0
    /// Seconds the whole history takes to play at 1x.
    private static let playbackDuration = 30.0

    static let playbackSpeeds: [Double] = [0.5, 1, 2, 4]

    func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    private func startPlayback() {
        guard let summary else { return }
        if commitIndex >= summary.commitCount - 1 { commitIndex = 0 }
        isPlaying = true

        playbackTask = Task {
            while !Task.isCancelled, self.commitIndex < summary.commitCount - 1 {
                try? await Task.sleep(for: .seconds(1 / Self.stepsPerSecond))
                guard !Task.isCancelled else { break }
                // Refining mid-playback would queue git reads faster than they complete.
                self.scrub(to: self.commitIndex + self.commitsPerStep, refine: false)
            }
            self.isPlaying = false
            // Settle on an exact reading wherever playback stopped.
            self.scrub(to: self.commitIndex)
        }
    }

    /// A long history plays back in a fixed span rather than taking an hour, so the same
    /// speed setting means the same thing whatever repository is open.
    private var commitsPerStep: Int {
        guard let summary else { return 1 }
        let total = Self.playbackDuration * Self.stepsPerSecond
        return max(1, Int((Double(summary.commitCount) / total * playbackSpeed).rounded()))
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    // MARK: - Selection

    func select(_ id: FileID?) {
        guard selection != id else { return }
        selection = id
        refreshDetail()
    }

    private func refreshDetail() {
        detailTask?.cancel()
        guard let engine, let id = selection else {
            detail = nil
            return
        }
        let index = commitIndex
        detailTask = Task {
            let detail = await engine.detail(for: id, at: index)
            guard !Task.isCancelled, index == self.commitIndex else { return }
            self.detail = detail
        }
    }

    func revealSelectionInFinder() {
        guard let repositoryURL, let path = detail?.snapshot.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([repositoryURL.appending(path: path)])
    }

    func copySelectionPath() {
        guard let path = detail?.snapshot.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    // MARK: - Derived values for the UI

    var currentCommit: CommitSummary? {
        guard let summary, summary.commits.indices.contains(commitIndex) else { return nil }
        return summary.commits[commitIndex]
    }

    /// Escape peels one layer of state off at a time, outermost first.
    func clearFocus() {
        if !searchText.isEmpty {
            searchText = ""
        } else if highlightedAuthor != nil {
            highlightedAuthor = nil
        } else if selection != nil {
            select(nil)
        } else if !mapRoot.isEmpty {
            mapRoot.removeLast()
        }
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// Partner files of the current selection, by how tightly they are coupled to it.
    var coupledFiles: [FileID: Double] {
        guard let coupling = detail?.coupling else { return [:] }
        return Dictionary(coupling.map { ($0.id, $0.degree) }, uniquingKeysWith: { first, _ in first })
    }

    /// Files matching the search box. Nil when there is no active search, which the map
    /// reads as "do not dim anything".
    var searchMatches: Set<FileID>? {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return nil }
        return Set(hotspots.filter { $0.path.lowercased().contains(query) }.map(\.id))
    }
}
