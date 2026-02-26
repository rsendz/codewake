//
//  SnapshotEngineTests.swift
//  codewake
//
//  Created by Luis Resendez on 20/02/2026.
//

import Foundation
import Testing

@testable import CodewakeKit

/// Builds histories by hand so scrubbing can be checked against known outcomes.
enum HistoryFixture {
    static func commit(
        _ sha: String,
        author: String = "Ada",
        at seconds: TimeInterval = 0,
        _ changes: [FileChange]
    ) -> Commit {
        Commit(
            sha: sha,
            authorName: author,
            authorEmail: "\(author.lowercased())@example.com",
            date: Date(timeIntervalSince1970: seconds),
            subject: "commit \(sha)",
            changes: changes
        )
    }

    static func added(_ path: String, _ lines: Int, blob: String? = nil) -> FileChange {
        FileChange(path: path, insertions: lines, deletions: 0, kind: .added, blobSHA: blob ?? "blob-\(path)-add")
    }

    static func modified(_ path: String, added: Int, removed: Int, blob: String? = nil) -> FileChange {
        FileChange(
            path: path, insertions: added, deletions: removed, kind: .modified,
            blobSHA: blob ?? "blob-\(path)-\(added)-\(removed)"
        )
    }

    static func deleted(_ path: String, lines: Int) -> FileChange {
        FileChange(path: path, insertions: 0, deletions: lines, kind: .deleted, blobSHA: nil)
    }

    static func renamed(_ from: String, to: String, added: Int = 0, removed: Int = 0) -> FileChange {
        FileChange(
            path: to, insertions: added, deletions: removed, kind: .renamed(from: from),
            blobSHA: "blob-\(to)"
        )
    }

    /// An add, edits, a rename, a delete, and a resurrection — one of each identity case.
    static var mixed: RepositoryHistory {
        RepositoryHistory(name: "fixture", commits: [
            commit("c0", at: 0, [added("src/app.swift", 10), added("README.md", 5)]),
            commit("c1", author: "Grace", at: 100, [modified("src/app.swift", added: 4, removed: 2)]),
            commit("c2", at: 200, [renamed("src/app.swift", to: "src/core/app.swift", added: 1, removed: 1)]),
            commit("c3", author: "Grace", at: 300, [added("src/core/util.swift", 20), deleted("README.md", lines: 5)]),
            commit("c4", at: 400, [modified("src/core/util.swift", added: 6, removed: 3)]),
            commit("c5", at: 500, [added("README.md", 8)]),
        ])
    }
}

@Suite("Snapshot engine")
struct SnapshotEngineTests {
    /// The whole scrubbing design rests on unapply being the exact inverse of apply. If
    /// this ever fails, dragging backwards quietly reports different numbers than dragging
    /// forwards to the same commit.
    @Test("Scrubbing backwards lands where scrubbing forwards did")
    func bidirectionalEquivalence() {
        let history = HistoryFixture.mixed

        for target in -1..<history.commitCount {
            var forward = SnapshotEngine(history: history)
            forward.move(to: target)

            var backward = SnapshotEngine(history: history)
            backward.move(to: history.commitCount - 1)
            backward.move(to: target)

            #expect(forward.currentSnapshot().files == backward.currentSnapshot().files)
            #expect(forward.totalLines == backward.totalLines)
            #expect(forward.aliveFileCount == backward.aliveFileCount)
        }
    }

    @Test("Random walks stay consistent with a fresh replay")
    func randomWalk() {
        let history = HistoryFixture.mixed
        var walker = SnapshotEngine(history: history)
        var generator = SystemRandomNumberGenerator()

        for _ in 0..<200 {
            let target = Int.random(in: -1..<history.commitCount, using: &generator)
            walker.move(to: target)

            var fresh = SnapshotEngine(history: history)
            fresh.move(to: target)
            #expect(walker.currentSnapshot().files == fresh.currentSnapshot().files)
        }
    }

    @Test("Churn accumulates and lines track the running difference")
    func accumulation() throws {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: 1)

        let app = try #require(engine.currentSnapshot().files.first { $0.path == "src/app.swift" })
        #expect(app.churn == 16)  // 10 added, then 4 added and 2 removed
        #expect(app.approximateLines == 12)
        #expect(app.commitCount == 2)
    }

    @Test("A renamed file keeps its identity and its history")
    func renameKeepsIdentity() throws {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: 2)
        let snapshot = engine.currentSnapshot()

        #expect(snapshot.files.contains { $0.path == "src/core/app.swift" })
        #expect(!snapshot.files.contains { $0.path == "src/app.swift" })

        let app = try #require(snapshot.files.first { $0.path == "src/core/app.swift" })
        #expect(app.churn == 18)      // carried across the rename, not restarted
        #expect(app.commitCount == 3)
    }

    @Test("The path shown is the path the file had at that commit")
    func pathAtCommit() {
        let history = HistoryFixture.mixed
        let app = history.files[0]
        #expect(app.path(at: 0) == "src/app.swift")
        #expect(app.path(at: 1) == "src/app.swift")
        #expect(app.path(at: 2) == "src/core/app.swift")
        #expect(app.path(at: 5) == "src/core/app.swift")
        #expect(app.wasRenamed)
    }

    @Test("Deleted files leave the snapshot and come back on resurrection")
    func deletionAndResurrection() throws {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)

        engine.move(to: 3)
        #expect(!engine.currentSnapshot().files.contains { $0.path == "README.md" })

        engine.move(to: 5)
        let readme = try #require(engine.currentSnapshot().files.first { $0.path == "README.md" })
        // Same file identity, so its earlier life still counts toward its churn.
        #expect(readme.churn == 18)
        #expect(readme.commitCount == 3)
        #expect(readme.approximateLines == 8)
    }

    @Test("Position -1 is an empty repository")
    func beforeFirstCommit() {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: 3)
        engine.move(to: -1)

        #expect(engine.currentSnapshot().files.isEmpty)
        #expect(engine.totalLines == 0)
        #expect(engine.aliveFileCount == 0)
    }

    @Test("Moving past either end clamps to the range")
    func clamping() {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: 9_000)
        #expect(engine.commitIndex == HistoryFixture.mixed.commitCount - 1)
        engine.move(to: -9_000)
        #expect(engine.commitIndex == -1)
    }

    @Test("Top files are ranked by churn")
    func ranking() {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: 4)

        let top = engine.topFilesByChurn(limit: 2)
        #expect(top.count == 2)
        #expect(top[0].churn >= top[1].churn)
        #expect(top[0].path == "src/core/util.swift")  // 20 + 9
    }

    @Test("Snapshots carry the blob of the file's most recent change")
    func blobTracking() throws {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: 1)
        let app = try #require(engine.currentSnapshot().files.first { $0.path == "src/app.swift" })
        #expect(app.blobSHA == "blob-src/app.swift-4-2")
    }
}
