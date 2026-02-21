//
//  AppState.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import CodewakerKit
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

    private(set) var phase: Phase = .welcome
    private(set) var summary: RepositorySummary?
    private(set) var hotspots: [Hotspot] = []
    private(set) var statistics: SnapshotStatistics?
    private(set) var isRefining = false

    var commitIndex: Int = 0
    private(set) var selection: FileID?
    private(set) var detail: FileDetail?
    private(set) var isPlaying = false

    private var engine: AnalysisEngine?
    private var refineTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    /// How long the playhead must sit still before spending git reads on exact complexity.
    private let refineDelay = Duration.milliseconds(180)

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
                self.commitIndex = engine.summary.commitCount - 1
                self.selection = nil
                self.detail = nil
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
    ///     CODEWAKER_REPO=~/some/repo swift run codewaker
    ///     swift run codewaker -repo ~/some/repo
    ///
    /// Deliberately not a bare positional path: AppKit reads an argument like that as a
    /// request to open a document, and SwiftUI then withholds the `WindowGroup` window
    /// waiting for a document scene that never arrives — the app runs with no window at
    /// all. A `-flag` argument goes to the user defaults argument domain instead, which is
    /// harmless, so `-repo` is read straight back out of `UserDefaults`.
    func openLaunchRepository() {
        let flag = UserDefaults.standard.string(forKey: "repo")
        let environment = ProcessInfo.processInfo.environment["CODEWAKER_REPO"]
        guard let path = flag ?? environment, !path.isEmpty else { return }
        open(URL(filePath: NSString(string: path).expandingTildeInPath))
    }

    func closeRepository() {
        loadTask?.cancel()
        stopPlayback()
        refineTask?.cancel()
        engine = nil
        summary = nil
        hotspots = []
        statistics = nil
        selection = nil
        detail = nil
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
    }

    func step(by delta: Int) {
        scrub(to: commitIndex + delta)
    }

    // MARK: - Playback

    /// Commits per second during playback. Fast enough to feel like footage, slow enough
    /// that the treemap reads as changing rather than flickering.
    private static let playbackRate = 24.0

    func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    private func startPlayback() {
        guard let summary else { return }
        if commitIndex >= summary.commitCount - 1 { commitIndex = 0 }
        isPlaying = true

        playbackTask = Task {
            // A long history plays back in a fixed span rather than taking an hour.
            let stride = max(1, summary.commitCount / 600)
            while !Task.isCancelled, self.commitIndex < summary.commitCount - 1 {
                try? await Task.sleep(for: .seconds(1 / Self.playbackRate))
                guard !Task.isCancelled else { break }
                // Refining mid-playback would queue git reads faster than they complete.
                self.scrub(to: self.commitIndex + stride, refine: false)
            }
            self.isPlaying = false
            // Settle on an exact reading wherever playback stopped.
            self.scrub(to: self.commitIndex)
        }
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

    // MARK: - Derived values for the UI

    var currentCommit: CommitSummary? {
        guard let summary, summary.commits.indices.contains(commitIndex) else { return nil }
        return summary.commits[commitIndex]
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }
}
