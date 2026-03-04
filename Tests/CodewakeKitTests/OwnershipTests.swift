//
//  OwnershipTests.swift
//  codewake
//
//  Created by Luis Resendez on 04/03/2026.
//

import Foundation
import Testing

@testable import CodewakeKit

@Suite("Ownership")
struct OwnershipTests {
    /// Ada writes and keeps `solo.swift` to herself; `shared.swift` is a committee, with
    /// Grace slightly ahead; Grace alone owns `grace.swift`.
    private var history: RepositoryHistory {
        var commits: [Commit] = [
            HistoryFixture.commit("c0", author: "Ada", [
                HistoryFixture.added("src/solo.swift", 100),
                HistoryFixture.added("src/shared.swift", 40),
            ]),
            HistoryFixture.commit("c1", author: "Grace", [
                HistoryFixture.added("src/grace.swift", 10),
            ]),
        ]
        for index in 0..<3 {
            commits.append(HistoryFixture.commit("ada\(index)", author: "Ada", [
                HistoryFixture.modified("src/solo.swift", added: 2, removed: 1),
            ]))
        }
        // shared.swift: Grace 3, Ada 1 (the add), Linus 2 — Grace owns it, nobody solely.
        for index in 0..<3 {
            commits.append(HistoryFixture.commit("gs\(index)", author: "Grace", [
                HistoryFixture.modified("src/shared.swift", added: 1, removed: 0),
            ]))
        }
        for index in 0..<2 {
            commits.append(HistoryFixture.commit("ls\(index)", author: "Linus", [
                HistoryFixture.modified("src/shared.swift", added: 1, removed: 0),
            ]))
        }
        return RepositoryHistory(name: "fixture", commits: commits)
    }

    private func report(at index: Int? = nil) -> OwnershipReport {
        var engine = SnapshotEngine(history: history)
        engine.move(to: index ?? history.commitCount - 1)
        return engine.ownership()
    }

    private func file(_ path: String, in report: OwnershipReport) throws -> FileOwnership {
        try #require(report.files.first { $0.path == path })
    }

    @Test("A file only one person has touched is reported as solely authored")
    func soleAuthorship() throws {
        let report = report()
        let solo = try file("src/solo.swift", in: report)
        #expect(solo.owner == "Ada")
        #expect(solo.authorCount == 1)
        #expect(solo.isSoleAuthored)
        #expect(solo.share == 1)
        #expect(solo.commits == 4)
    }

    @Test("The author with the most commits owns a file even without a majority")
    func dominantAuthor() throws {
        let shared = try file("src/shared.swift", in: report())
        #expect(shared.owner == "Grace")
        #expect(shared.authorCount == 3)
        #expect(!shared.isSoleAuthored)
        #expect(shared.ownerCommits == 3)
        #expect(shared.commits == 6)
        #expect(abs(shared.share - 0.5) < 0.0001)
    }

    @Test("Totals count only the files nobody else has touched")
    func totals() {
        let report = report()
        #expect(report.totalFiles == 3)
        // solo.swift (100 + 3 net) and grace.swift (10) are sole-authored; shared is not.
        #expect(report.soleAuthoredFiles == 2)
        #expect(report.soleAuthoredLines == 113)
        #expect(report.totalLines == 158)
        #expect(abs(report.soleAuthoredLineShare - 113.0 / 158.0) < 0.0001)
    }

    @Test("Authors are ranked by how much of the codebase they own")
    func authorRanking() throws {
        let report = report()
        #expect(report.authors.map(\.name) == ["Ada", "Grace", "Linus"])

        let ada = try #require(report.authors.first)
        #expect(ada.ownedFiles == 1)
        #expect(ada.ownedLines == 103)
        #expect(ada.soleAuthoredFiles == 1)
        // Ada created shared.swift, so she has touched two files while owning one.
        #expect(ada.touchedFiles == 2)

        let linus = try #require(report.authors.last)
        #expect(linus.ownedFiles == 0)
        #expect(linus.touchedFiles == 1)
    }

    @Test("The bus factor counts the owners it takes to cover half the codebase")
    func busFactor() {
        // Ada owns 103 of 158 lines on her own, which is already past half.
        #expect(report().busFactor == 1)

        let spread = (0..<4).map { index in
            AuthorOwnership(
                name: "author\(index)", ownedFiles: 1, ownedLines: 25,
                soleAuthoredFiles: 0, soleAuthoredLines: 0, touchedFiles: 1
            )
        }
        #expect(SnapshotEngine.busFactor(authors: spread, totalLines: 100) == 2)
        #expect(SnapshotEngine.busFactor(authors: [], totalLines: 0) == 0)
    }

    @Test("Ownership is measured as of the playhead, not the end of history")
    func ownershipMovesWithTheTimeline() throws {
        // Before Grace's first edit, shared.swift belongs to Ada alone.
        let early = report(at: 4)
        let shared = try file("src/shared.swift", in: early)
        #expect(shared.owner == "Ada")
        #expect(shared.isSoleAuthored)
        #expect(early.authors.map(\.name) == ["Ada", "Grace"])
    }

    @Test("A deleted file leaves the report")
    func deletedFilesAreExcluded() {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: 3)  // README.md is deleted here
        let report = engine.ownership()
        #expect(!report.files.contains { $0.path == "README.md" })
        #expect(report.totalFiles == engine.aliveFileCount)
    }

    @Test("An empty repository reports nothing rather than failing")
    func emptyHistory() {
        var engine = SnapshotEngine(history: HistoryFixture.mixed)
        engine.move(to: -1)
        let report = engine.ownership()
        #expect(report.files.isEmpty)
        #expect(report.authors.isEmpty)
        #expect(report.busFactor == 0)
        #expect(report.ownership(of: 0) == nil)
    }

    @Test("Every file can be found by id")
    func lookupByID() throws {
        let report = report()
        let solo = try file("src/solo.swift", in: report)
        #expect(report.ownership(of: solo.id) == solo)
    }
}
