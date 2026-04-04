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

// MARK: - Change coupling

extension SnapshotEngine {
    /// Files that tend to change in the same commits as `id`, as of the current position.
    ///
    /// This needs no extra bookkeeping and no precomputed pair index: the file's own event
    /// list already names every commit that touched it, and each of those commits already
    /// names every other file it touched. Walking that is proportional to the file's own
    /// history rather than the repository's, which is why coupling can be answered on
    /// demand for whatever the user just clicked instead of maintained for every pair.
    public func coupling(for id: FileID, options: CouplingOptions = .default) -> [CouplingLink] {
        guard states.indices.contains(id) else { return [] }
        let events = history.files[id].events.prefix(states[id].appliedEvents)

        var shared: [FileID: Int] = [:]
        var ownCommits = 0
        for event in events {
            let touched = history.touchedFiles[event.commitIndex]
            guard touched.count <= options.maximumFilesPerCommit else { continue }
            ownCommits += 1
            for other in touched where other != id {
                shared[other, default: 0] += 1
            }
        }
        guard ownCommits > 0 else { return [] }

        return shared.compactMap { partner, count -> CouplingLink? in
            guard count >= options.minimumSharedCommits, isAlive(partner) else { return nil }
            return CouplingLink(
                id: partner,
                path: history.files[partner].path(at: commitIndex),
                sharedCommits: count,
                partnerCommits: states[partner].appliedEvents,
                degree: Double(count) / Double(ownCommits)
            )
        }
        .sorted { ($0.degree, $0.sharedCommits) > ($1.degree, $1.sharedCommits) }
        .prefix(options.limit)
        .map { $0 }
    }
}

// MARK: - Ownership

extension SnapshotEngine {
    /// Who owns what across the whole repository, as of the current position.
    ///
    /// Unlike coupling, this cannot be answered for one file on demand — the question is
    /// about the shape of the whole codebase — so it walks every live file's applied
    /// events once. That is a pass over the history that has actually been scrubbed
    /// through, which is why the caller runs it when the playhead settles rather than on
    /// every frame, and caches the answer per position.
    public func ownership() -> OwnershipReport {
        var files: [FileOwnership] = []
        files.reserveCapacity(aliveFileCount)

        var accumulators: [String: AuthorAccumulator] = [:]
        var soleAuthoredFiles = 0
        var soleAuthoredLines = 0
        var totalLines = 0

        // One scratch dictionary reused across files, so counting authors per file does not
        // allocate a fresh table for each of thousands of files.
        var counts: [String: Int] = [:]

        for id in 0..<states.count where isAlive(id) {
            let applied = states[id].appliedEvents
            guard applied > 0 else { continue }

            counts.removeAll(keepingCapacity: true)
            for event in history.files[id].events.prefix(applied) {
                counts[history.commits[event.commitIndex].authorName, default: 0] += 1
            }
            guard !counts.isEmpty else { continue }

            // Ties break on name, so the map does not change colour between two runs that
            // saw exactly the same history.
            let top = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }!
            let lines = max(states[id].lines, 0)
            let isSole = counts.count == 1

            files.append(FileOwnership(
                id: id,
                path: history.files[id].path(at: commitIndex),
                lines: lines,
                commits: applied,
                authorCount: counts.count,
                owner: top.key,
                ownerCommits: top.value
            ))

            totalLines += lines
            if isSole {
                soleAuthoredFiles += 1
                soleAuthoredLines += lines
            }

            for author in counts.keys {
                accumulators[author, default: AuthorAccumulator()].touchedFiles += 1
            }
            accumulators[top.key, default: AuthorAccumulator()].add(
                lines: lines, soleAuthored: isSole
            )
        }

        let authors = accumulators
            .map { $0.value.report(name: $0.key) }
            .sorted { ($0.ownedLines, $1.name) > ($1.ownedLines, $0.name) }

        return OwnershipReport(
            commitIndex: commitIndex,
            files: files.sorted { ($0.lines, $1.path) > ($1.lines, $0.path) },
            authors: authors,
            totalFiles: files.count,
            totalLines: totalLines,
            soleAuthoredFiles: soleAuthoredFiles,
            soleAuthoredLines: soleAuthoredLines,
            busFactor: Self.busFactor(authors: authors, totalLines: totalLines)
        )
    }

    /// How many of the biggest owners it takes to cover half the codebase.
    static func busFactor(authors: [AuthorOwnership], totalLines: Int) -> Int {
        guard totalLines > 0 else { return authors.isEmpty ? 0 : 1 }
        let half = Double(totalLines) / 2
        var covered = 0.0
        for (count, author) in authors.enumerated() {
            covered += Double(author.ownedLines)
            if covered >= half { return count + 1 }
        }
        return authors.count
    }

    private struct AuthorAccumulator {
        var ownedFiles = 0
        var ownedLines = 0
        var soleAuthoredFiles = 0
        var soleAuthoredLines = 0
        var touchedFiles = 0

        mutating func add(lines: Int, soleAuthored: Bool) {
            ownedFiles += 1
            ownedLines += lines
            if soleAuthored {
                soleAuthoredFiles += 1
                soleAuthoredLines += lines
            }
        }

        func report(name: String) -> AuthorOwnership {
            AuthorOwnership(
                name: name,
                ownedFiles: ownedFiles,
                ownedLines: ownedLines,
                soleAuthoredFiles: soleAuthoredFiles,
                soleAuthoredLines: soleAuthoredLines,
                touchedFiles: touchedFiles
            )
        }
    }
}

// MARK: - Age

extension SnapshotEngine {
    /// How long each live file has gone untouched, as of the current position.
    ///
    /// Every file's last applied event is already the cursor the engine maintains for
    /// scrubbing, so this is one array lookup per live file with no history to walk. That
    /// does not show up on a repository whose files have short histories — the per-file work
    /// dominates and this lands level with ownership — but it is what keeps the cost flat as
    /// those histories get long. Same shape of question as ownership, same route through the
    /// UI.
    public func ages() -> AgeReport {
        guard commitIndex >= 0, !history.commits.isEmpty else { return .empty }
        let now = history.commits[commitIndex].date
        // Ages are read as a share of how long the repository had existed by this point, not
        // in absolute years. A six-month-old project and a fifteen-year-old one then use the
        // same full range of colour, and "old for this codebase" means what it says.
        let span = max(now.timeIntervalSince(history.commits[0].date), 1)

        var files: [FileAge] = []
        files.reserveCapacity(aliveFileCount)
        var byDirectory: [String: (files: Int, lines: Int, ages: [TimeInterval])] = [:]
        var totalLines = 0
        var dormantFiles = 0
        var dormantLines = 0

        for id in 0..<states.count where isAlive(id) {
            let applied = states[id].appliedEvents
            guard applied > 0 else { continue }
            let event = history.files[id].events[applied - 1]
            let lastTouched = history.commits[event.commitIndex].date
            let age = max(now.timeIntervalSince(lastTouched), 0)
            let path = history.files[id].path(at: commitIndex)
            let lines = max(states[id].lines, 0)

            files.append(FileAge(
                id: id,
                path: path,
                lines: lines,
                lastTouchedIndex: event.commitIndex,
                lastTouched: lastTouched,
                age: age,
                share: min(age / span, 1)
            ))

            let components = path.split(separator: "/")
            let directory = components.count > 1 ? String(components[0]) : "/"
            byDirectory[directory, default: (0, 0, [])].files += 1
            byDirectory[directory]!.lines += lines
            byDirectory[directory]!.ages.append(age)

            totalLines += lines
            if age >= AgeReport.dormantAfter {
                dormantFiles += 1
                dormantLines += lines
            }
        }

        let directories = byDirectory
            .map { name, value in
                DirectoryAge(
                    name: name, files: value.files, lines: value.lines,
                    medianAge: medianInterval(value.ages)
                )
            }
            .sorted { ($0.medianAge, $1.name) > ($1.medianAge, $0.name) }

        return AgeReport(
            commitIndex: commitIndex,
            now: now,
            span: span,
            files: files.sorted { ($0.lines, $1.path) > ($1.lines, $0.path) },
            directories: directories,
            totalLines: totalLines,
            medianAge: medianInterval(files.map(\.age)),
            dormantFiles: dormantFiles,
            dormantLines: dormantLines
        )
    }

    private func medianInterval(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
