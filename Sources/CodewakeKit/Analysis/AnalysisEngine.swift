//
//  AnalysisEngine.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
//

import Foundation

/// Commit metadata without the per-file changes, cheap enough for the UI to hold all of.
public struct CommitSummary: Sendable, Identifiable, Hashable {
    public let index: Int
    public let sha: String
    public let authorName: String
    public let date: Date
    public let subject: String
    public let churn: Int
    public let filesTouched: Int

    public var id: Int { index }
    public var shortSHA: String { String(sha.prefix(7)) }
}

public struct RepositorySummary: Sendable {
    public let name: String
    public let commits: [CommitSummary]
    public let fileCount: Int
    /// Everyone who ever committed, busiest first, fixed for the life of the repository.
    ///
    /// The ownership map colours people by their position in this list. Ranking them by
    /// what they own *at the current position* would look more relevant and be much worse:
    /// that order changes as the playhead moves, so files would change colour while
    /// scrubbing for reasons that have nothing to do with who owns them.
    public let authorRanking: [String]

    public var commitCount: Int { commits.count }
    public var dateRange: ClosedRange<Date> { commits[0].date...commits[commits.count - 1].date }
}

public struct ChurnPoint: Sendable, Hashable {
    public let commitIndex: Int
    public let date: Date
    public let churn: Int
}

public struct AuthorShare: Sendable, Identifiable, Hashable {
    public let name: String
    public let commits: Int
    public var id: String { name }
}

/// Everything the inspector shows about one file at one point in history.
public struct FileDetail: Sendable {
    public let snapshot: FileSnapshot
    public let complexity: ComplexityScore?
    public let churnHistory: [ChurnPoint]
    public let recentCommits: [CommitSummary]
    /// Commit counts by author, busiest first — the seed of a future ownership view.
    public let authors: [AuthorShare]
    /// Files that tend to change in the same commits as this one.
    public let coupling: [CouplingLink]
    public let wasRenamed: Bool
}

public enum LoadPhase: Sendable {
    case readingHistory
    case buildingTimelines
    case ready
}

public struct SnapshotStatistics: Sendable, Hashable {
    public let commitIndex: Int
    public let fileCount: Int
    public let totalLines: Int
}

/// Owns the loaded repository and answers questions about it at any point in history.
///
/// The UI drives this with two kinds of call: `hotspots(at:)` during a drag, which only
/// reads complexity that is already cached so it can keep up with the playhead, and
/// `refinedHotspots(at:)` once the playhead settles, which is allowed to read blobs.
public actor AnalysisEngine {
    /// How many files the hotspot view considers. Past this, rectangles are too small to
    /// read and the extra analysis buys nothing.
    public static let hotspotLimit = 250

    private let provider: any HistoryProvider
    private var snapshots: SnapshotEngine
    private let complexity = ComplexityCache()
    /// Ownership costs a pass over every live file's history, so the answer for a position
    /// is kept until the playhead moves off it.
    private var ownershipCache: OwnershipReport?
    /// Immutable once loaded, so the UI can read repository metadata without awaiting.
    public nonisolated let summary: RepositorySummary

    private init(provider: any HistoryProvider, history: RepositoryHistory, summary: RepositorySummary) {
        self.provider = provider
        self.snapshots = SnapshotEngine(history: history)
        self.summary = summary
    }

    public static func load(
        from provider: any HistoryProvider,
        filter: FileFilter = .default,
        progress: @Sendable (LoadPhase) -> Void = { _ in }
    ) async throws -> AnalysisEngine {
        progress(.readingHistory)
        let commits = try await provider.loadCommits()

        progress(.buildingTimelines)
        let history = RepositoryHistory(name: provider.name, commits: commits, filter: filter)

        let summaries = commits.enumerated().map { index, commit -> CommitSummary in
            // Counted after filtering, so the timeline's activity graph shows the shape of
            // the work rather than a spike everywhere a lock file was regenerated.
            let counted = commit.changes.filter { filter.includes($0.path) }
            let churn = counted.reduce(0) { $0 + $1.churn }
            return CommitSummary(
                index: index,
                sha: commit.sha,
                authorName: commit.authorName,
                date: commit.date,
                subject: commit.subject,
                churn: churn,
                filesTouched: counted.count
            )
        }

        var commitsByAuthor: [String: Int] = [:]
        for commit in commits { commitsByAuthor[commit.authorName, default: 0] += 1 }
        // Ties break on name so two runs over the same history assign the same colours.
        let ranking = commitsByAuthor
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map(\.key)

        let summary = RepositorySummary(
            name: history.name,
            commits: summaries,
            fileCount: history.files.count,
            authorRanking: ranking
        )

        progress(.ready)
        return AnalysisEngine(provider: provider, history: history, summary: summary)
    }

    // MARK: - Scrubbing

    public var commitIndex: Int { snapshots.commitIndex }

    /// Everything the view needs for one scrub position, in a single hop.
    public struct ScrubResult: Sendable {
        public let commitIndex: Int
        public let hotspots: [Hotspot]
        public let statistics: SnapshotStatistics
        /// True when some complexity is still a size estimate, so the caller knows a
        /// refined pass would tell it something new.
        public var isEstimated: Bool { hotspots.contains(where: \.isEstimated) }
    }

    /// The fast path, for while the user is dragging: no I/O, no suspension.
    public func scrub(to index: Int) -> ScrubResult {
        let files = topFiles(at: index)
        let scores = complexity.cachedScores(for: files.compactMap(\.blobSHA))
        return result(files: files, scores: scores)
    }

    /// The settled path: reads any blobs still missing, then rescores.
    public func refine(at index: Int) async throws -> ScrubResult {
        // `files` is captured before the await, so the answer describes `index` even if the
        // playhead moves on while blobs are being read.
        let files = topFiles(at: index)
        let shas = files.compactMap(\.blobSHA)
        try await fetchComplexity(for: shas)
        return result(files: files, scores: complexity.cachedScores(for: shas))
    }

    private func result(files: [FileSnapshot], scores: [String: ComplexityScore]) -> ScrubResult {
        ScrubResult(
            commitIndex: snapshots.commitIndex,
            hotspots: HotspotAnalyzer.analyze(files: files, complexity: scores),
            statistics: SnapshotStatistics(
                commitIndex: snapshots.commitIndex,
                fileCount: snapshots.aliveFileCount,
                totalLines: snapshots.totalLines
            )
        )
    }

    /// Hotspots at `index` using only complexity already in the cache. Never waits on git,
    /// so this keeps up while the user drags.
    public func hotspots(at index: Int) -> [Hotspot] {
        let files = topFiles(at: index)
        let scores = complexity.cachedScores(for: files.compactMap(\.blobSHA))
        return HotspotAnalyzer.analyze(files: files, complexity: scores)
    }

    /// Hotspots at `index` with any missing complexity read from git first. Call this once
    /// the playhead settles; the result supersedes the estimated one.
    public func refinedHotspots(at index: Int) async throws -> [Hotspot] {
        // `files` is captured before the await, so the answer describes `index` even if the
        // playhead moves on while blobs are being read.
        let files = topFiles(at: index)
        let shas = files.compactMap(\.blobSHA)
        try await fetchComplexity(for: shas)
        return HotspotAnalyzer.analyze(files: files, complexity: complexity.cachedScores(for: shas))
    }

    private func fetchComplexity(for shas: [String]) async throws {
        let unknown = complexity.unknownSHAs(among: shas)
        guard !unknown.isEmpty else { return }
        let blobs = try await provider.loadBlobs(shas: unknown)
        complexity.store(blobs: blobs, requested: unknown)
    }

    // MARK: - Ownership

    /// Who owns what across the whole repository at `index`.
    ///
    /// Only worth asking once the playhead settles: it walks every live file rather than
    /// the top few hundred, which is too much work to repeat inside a drag.
    public func ownership(at index: Int) -> OwnershipReport {
        snapshots.move(to: index)
        if let cached = ownershipCache, cached.commitIndex == snapshots.commitIndex {
            return cached
        }
        let report = snapshots.ownership()
        ownershipCache = report
        return report
    }

    public func statistics(at index: Int) -> SnapshotStatistics {
        snapshots.move(to: index)
        return SnapshotStatistics(
            commitIndex: snapshots.commitIndex,
            fileCount: snapshots.aliveFileCount,
            totalLines: snapshots.totalLines
        )
    }

    private func topFiles(at index: Int) -> [FileSnapshot] {
        snapshots.move(to: index)
        return snapshots.topFilesByChurn(limit: Self.hotspotLimit)
    }

    // MARK: - Inspecting

    public func detail(for id: FileID, at index: Int) async -> FileDetail? {
        snapshots.move(to: index)
        guard let snapshot = snapshots.snapshot(for: id) else { return nil }

        let timeline = snapshots.history.file(id)
        let applied = timeline.events.prefix { $0.commitIndex <= snapshots.commitIndex }

        var authorCounts: [String: Int] = [:]
        for event in applied {
            authorCounts[summary.commits[event.commitIndex].authorName, default: 0] += 1
        }
        let authors = authorCounts
            .map { AuthorShare(name: $0.key, commits: $0.value) }
            .sorted { ($0.commits, $1.name) > ($1.commits, $0.name) }

        var score: ComplexityScore?
        if let sha = snapshot.blobSHA {
            try? await fetchComplexity(for: [sha])
            score = complexity.cachedScores(for: [sha])[sha]
        }

        return FileDetail(
            snapshot: snapshot,
            complexity: score,
            churnHistory: applied.map { event in
                ChurnPoint(
                    commitIndex: event.commitIndex,
                    date: summary.commits[event.commitIndex].date,
                    churn: event.churn
                )
            },
            recentCommits: applied.suffix(8).reversed().map { summary.commits[$0.commitIndex] },
            authors: authors,
            coupling: snapshots.coupling(for: id),
            wasRenamed: timeline.wasRenamed
        )
    }
}
