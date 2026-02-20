//
//  SnapshotEngine.swift
//  codewake
//
//  Created by Luis Resendez on 20/02/2026.
//

import Foundation

/// Maintains the repository's state at a scrub position, moving incrementally.
///
/// Scrubbing from commit `i` to `j` applies or unapplies only the commits between them,
/// so the cost is proportional to the files those commits touched rather than to the size
/// of the repository. Every quantity tracked here is either additive (churn, lines) or a
/// count of applied events, which makes stepping backwards exactly as cheap and exactly as
/// accurate as stepping forwards — no undo log required.
public struct SnapshotEngine: Sendable {
    /// Per-file accumulators. `appliedEvents` doubles as the file's commit count and as the
    /// cursor that determines whether it currently exists and which blob it points at.
    private struct FileState {
        var appliedEvents = 0
        var churn = 0
        var lines = 0
    }

    public let history: RepositoryHistory
    private var states: [FileState]
    /// -1 means "before the first commit", i.e. an empty repository.
    public private(set) var commitIndex: Int = -1
    /// Running totals, kept up to date by `apply`/`unapply` so the UI can read repository
    /// stats every frame without scanning every file.
    public private(set) var aliveFileCount = 0
    public private(set) var totalLines = 0

    public init(history: RepositoryHistory) {
        self.history = history
        self.states = Array(repeating: FileState(), count: history.files.count)
    }

    public var commitCount: Int { history.commitCount }

    // MARK: - Scrubbing

    /// Moves to `target`, clamped to the valid range. Returns the number of commits stepped.
    @discardableResult
    public mutating func move(to target: Int) -> Int {
        let destination = min(max(target, -1), history.commitCount - 1)
        let distance = abs(destination - commitIndex)

        while commitIndex < destination {
            apply(commitIndex + 1)
            commitIndex += 1
        }
        while commitIndex > destination {
            unapply(commitIndex)
            commitIndex -= 1
        }
        return distance
    }

    private mutating func apply(_ index: Int) {
        for id in history.touchedFiles[index] {
            let wasAlive = isAlive(id)
            let event = history.files[id].events[states[id].appliedEvents]
            states[id].appliedEvents += 1
            states[id].churn += event.churn

            let delta = event.insertions - event.deletions
            states[id].lines += delta
            totalLines += delta
            updateAliveCount(wasAlive: wasAlive, isAlive: !event.isDeletion)
        }
    }

    private mutating func unapply(_ index: Int) {
        // Reverse order, so a commit that touched the same path twice unwinds correctly.
        for id in history.touchedFiles[index].reversed() {
            let wasAlive = isAlive(id)
            states[id].appliedEvents -= 1
            let event = history.files[id].events[states[id].appliedEvents]
            states[id].churn -= event.churn

            let delta = event.insertions - event.deletions
            states[id].lines -= delta
            totalLines -= delta
            updateAliveCount(wasAlive: wasAlive, isAlive: isAlive(id))
        }
    }

    private mutating func updateAliveCount(wasAlive: Bool, isAlive: Bool) {
        if wasAlive == isAlive { return }
        aliveFileCount += isAlive ? 1 : -1
    }

    // MARK: - Reading

    /// Whether the file exists at the current position: it has been touched at least once,
    /// and its most recent touch was not a deletion.
    private func isAlive(_ id: FileID) -> Bool {
        let applied = states[id].appliedEvents
        guard applied > 0 else { return false }
        return !history.files[id].events[applied - 1].isDeletion
    }

    private func snapshot(of id: FileID) -> FileSnapshot {
        let state = states[id]
        let timeline = history.files[id]
        return FileSnapshot(
            id: id,
            path: timeline.path(at: commitIndex),
            churn: state.churn,
            commitCount: state.appliedEvents,
            approximateLines: max(state.lines, 0),
            blobSHA: state.appliedEvents > 0 ? timeline.events[state.appliedEvents - 1].blobSHA : nil
        )
    }

    /// Every file that exists at the current position.
    public func currentSnapshot() -> TimelineSnapshot {
        let files = (0..<states.count).lazy.filter(isAlive).map(snapshot(of:))
        return TimelineSnapshot(commitIndex: commitIndex, files: Array(files))
    }

    /// The file at the current position, or nil if it does not exist here.
    public func snapshot(for id: FileID) -> FileSnapshot? {
        guard states.indices.contains(id), isAlive(id) else { return nil }
        return snapshot(of: id)
    }

    /// The `limit` files with the most churn, which is all the hotspot view needs and avoids
    /// materialising every file in a large repository on each scrub tick.
    public func topFilesByChurn(limit: Int) -> [FileSnapshot] {
        var ranked: [(id: FileID, churn: Int)] = []
        ranked.reserveCapacity(min(states.count, 4096))
        for id in 0..<states.count where isAlive(id) && states[id].churn > 0 {
            ranked.append((id, states[id].churn))
        }
        ranked.sort { $0.churn > $1.churn }
        return ranked.prefix(limit).map { snapshot(of: $0.id) }
    }
}
