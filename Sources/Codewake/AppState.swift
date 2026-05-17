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

/// Not a static on `AppState`: a stored property's initializer cannot refer to `Self`.
private let magnifierDefaultsKey = "magnifiesSmallTiles"

/// Drives the whole app: owns the engine, the scrub position, and what the views show.
///
/// Scrubbing runs on two tracks. Every position change immediately asks the engine for a
/// result built from cached complexity, which never suspends on git and so keeps up with
/// the drag. Once the playhead has been still for a moment, a second pass reads whatever
/// blobs are missing and replaces the estimate. Both tag their results with the position
/// they describe, so a slow refine landing late is discarded rather than shown.
///
/// The ownership and age maps run on a third track under the opposite rule: a late answer
/// is kept rather than discarded. `refreshDerivedView()` says why.
@MainActor
@Observable
final class AppState {
    enum Phase {
        case welcome
        case loading(Progress)
        case ready
        case failed(String)

        /// What to say while a repository is being read. The commit count is carried along
        /// so a large repository can be told it is a large repository, instead of leaving
        /// the user to wonder whether the app has hung.
        struct Progress {
            var message: String
            var commits: Int = 0

            var isSlow: Bool { commits >= LoadPhase.slowCommitCount }
        }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case map = "Map"
        case ownership = "Ownership"
        case age = "Age"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .map: "square.grid.2x2"
            case .ownership: "person.2"
            case .age: "clock.arrow.circlepath"
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
    /// Where the map is opened to. At repository scale the smallest files are a few points
    /// across: visible, but with no room for a name. Opening a directory hands its files the
    /// whole canvas, which is the level at which they can be read and worked with.
    ///
    /// The rules about which moves are legal live in `MapLocation`, in the kit, where they
    /// can be tested without a window.
    private(set) var location = MapLocation()
    var searchText: String = ""
    /// Whether hovering a rectangle too small to carry a name magnifies the area around it.
    ///
    /// Off until asked for. It follows the pointer everywhere, and a panel that opens each
    /// time the cursor crosses a small tile is in the way of reading the shape of the map,
    /// which is what most people are doing most of the time. Remembered across launches,
    /// because it is a preference about how you read a map rather than about the repository
    /// in front of you.
    var magnifiesSmallTiles: Bool = UserDefaults.standard.object(forKey: magnifierDefaultsKey) as? Bool ?? false {
        didSet { UserDefaults.standard.set(magnifiesSmallTiles, forKey: magnifierDefaultsKey) }
    }
    var isShowingHelp = false
    /// Bumped to ask the search field to take focus. A plain Bool would not re-fire when
    /// the shortcut is pressed twice in a row.
    private(set) var focusSearchToken = 0
    /// Multiplier on playback speed. At 1x the whole history plays in about 30 seconds.
    var playbackSpeed: Double = 1

    private var engine: AnalysisEngine?
    private var refineTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    /// Which position and view the derived maps should be showing. A single slot, always
    /// holding the newest request: the worker takes whatever is in it whenever it comes
    /// free, so intermediate positions are dropped rather than queued.
    private var derivedRequest: DerivedRequest?
    private var derivedWorker: Task<Void, Never>?
    /// Identifies the current worker, so a cancelled one tidying up on its way out cannot
    /// clear the state belonging to its replacement. Cancelling a task does not run its
    /// `defer` there and then — that happens whenever the task is next scheduled, which can
    /// be after a new worker has already taken over.
    private var derivedWorkerToken = 0
    private var playbackTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    private struct DerivedRequest {
        let index: Int
        let mode: ViewMode
    }

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
        cancelDerivedWork()
        stopPlayback()
        phase = .loading(Phase.Progress(message: "Opening…"))

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
                self.location = MapLocation()
                self.searchText = ""
                self.detail = nil
                self.ownership = nil
                self.ages = nil
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
        cancelDerivedWork()
        engine = nil
        summary = nil
        authorColors = AuthorColors(ranking: [])
        repositoryURL = nil
        hotspots = []
        statistics = nil
        selection = nil
        location = MapLocation()
        detail = nil
        ownership = nil
        ages = nil
        highlightedAuthor = nil
        searchText = ""
        phase = .welcome
    }

    private func report(_ loadPhase: LoadPhase) {
        switch loadPhase {
        case .counting:
            phase = .loading(Phase.Progress(message: "Counting commits…"))
        case .readingHistory(let commits):
            phase = .loading(Phase.Progress(message: "Reading history…", commits: commits))
        case .buildingTimelines(let commits):
            phase = .loading(Phase.Progress(message: "Building timelines…", commits: commits))
        case .ready:
            break
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
    /// on git's own history. Nothing here touches git, so the only reason to wait at all is
    /// to coalesce a fast drag.
    ///
    /// Requests are coalesced rather than cancelled and replaced, and a finished report is
    /// kept whether or not the playhead has moved on since it was asked for. Both matter for
    /// the same reason: a recompute has to make a round trip out to the engine's actor and
    /// back to the main actor, while playback moves the playhead every 50ms. Discarding a
    /// report that no longer describes `commitIndex` makes every update a race against the
    /// next step — and one lost on a repository large enough is lost every time after, so
    /// the map froze for the rest of playback while the counters above it kept moving. One
    /// worker draining a single-slot mailbox instead means a late answer is still the newest
    /// answer, and the map lands a step behind rather than not at all.
    private func refreshDerivedView() {
        guard let engine, viewMode != .map else {
            derivedRequest = nil
            isComputingDerived = false
            return
        }
        derivedRequest = DerivedRequest(index: commitIndex, mode: viewMode)
        guard derivedWorker == nil else { return }
        isComputingDerived = true
        derivedWorkerToken += 1
        let token = derivedWorkerToken

        derivedWorker = Task {
            defer {
                if token == derivedWorkerToken {
                    derivedWorker = nil
                    isComputingDerived = false
                }
            }
            // Coalesce a fast drag before the first pass. Playback is already rate-limited
            // to 20 steps a second, so waiting there just means never arriving.
            if !isPlaying {
                try? await Task.sleep(for: derivedDelay)
                guard !Task.isCancelled else { return }
            }

            // Draining rather than looping once: a position that arrives while this is
            // computing replaces the slot, and is picked up on the way round.
            while let request = derivedRequest {
                derivedRequest = nil
                switch request.mode {
                case .ownership:
                    let report = await engine.ownership(at: request.index)
                    guard !Task.isCancelled else { return }
                    // The view can have been switched away from while this was in flight.
                    // Drop the answer, but stay in the loop for whatever asked for the switch.
                    if viewMode == .ownership { ownership = report }
                case .age:
                    let report = await engine.ages(at: request.index)
                    guard !Task.isCancelled else { return }
                    if viewMode == .age { ages = report }
                case .map:
                    break
                }
            }
        }
    }

    /// Drops any derived work in flight, for when the repository under it is going away.
    private func cancelDerivedWork() {
        derivedWorker?.cancel()
        derivedWorker = nil
        derivedWorkerToken += 1
        derivedRequest = nil
        isComputingDerived = false
    }

    // MARK: - Opening a directory

    func open(directory name: String) {
        location.open(name, among: visiblePaths)
    }

    /// The inspector's lists are of the whole repository, so a row in one means a top-level
    /// directory rather than one inside wherever the map happens to be.
    func open(topLevelDirectory name: String) {
        location.openFromRoot(name, among: allPaths)
    }

    func closeDirectory(to depth: Int) {
        location.close(to: depth)
    }

    var mapRoot: [String] { location.components }

    /// Path prefix every visible file shares, with its trailing slash.
    var rootPrefix: String { location.prefix }

    /// The files the map is currently showing. Colour, ranking and the treemap's own scale
    /// all work from this rather than from the whole repository, so opening a directory
    /// re-reads its contents against each other instead of against the codebase.
    var visibleHotspots: [Hotspot] {
        location.isRoot ? hotspots : hotspots.filter { location.contains($0.path) }
    }

    /// Paths of the files the view on screen draws, before the location narrows them.
    ///
    /// Each map draws a different set: the hotspot map takes the busiest files, ownership
    /// and age take the largest. Navigation has to be answered against whichever one is in
    /// front of the user, or a directory that is plainly on screen refuses to open because
    /// it happens not to be in another view's selection.
    private var allPaths: [String] {
        switch viewMode {
        case .map: hotspots.map(\.path)
        case .ownership: (ownership?.files ?? []).map(\.path)
        case .age: (ages?.files ?? []).map(\.path)
        }
    }

    private var visiblePaths: [String] {
        allPaths.filter { location.contains($0) }
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
        } else {
            location.closeOne()
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
