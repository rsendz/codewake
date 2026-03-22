//
//  CouplingTests.swift
//  codewake
//
//  Created by Luis Resendez on 25/02/2026.
//

import Foundation
import Testing

@testable import CodewakeKit

@Suite("Change coupling")
struct CouplingTests {
    /// `pairs` change together every time; `loner` changes on its own.
    private var history: RepositoryHistory {
        var commits: [Commit] = []
        for index in 0..<6 {
            commits.append(HistoryFixture.commit("pair\(index)", [
                HistoryFixture.modified("src/view.swift", added: 5, removed: 1),
                HistoryFixture.modified("src/viewModel.swift", added: 4, removed: 2),
            ]))
        }
        for index in 0..<6 {
            commits.append(HistoryFixture.commit("solo\(index)", [
                HistoryFixture.modified("src/loner.swift", added: 3, removed: 1),
            ]))
        }
        // Two commits where the view also touches a rarely-related helper.
        for index in 0..<2 {
            commits.append(HistoryFixture.commit("helper\(index)", [
                HistoryFixture.modified("src/view.swift", added: 1, removed: 1),
                HistoryFixture.modified("src/helper.swift", added: 1, removed: 1),
            ]))
        }
        return RepositoryHistory(name: "fixture", commits: commits)
    }

    private func engine(at index: Int) -> SnapshotEngine {
        var engine = SnapshotEngine(history: history)
        engine.move(to: index)
        return engine
    }

    private func id(of path: String, in engine: SnapshotEngine) -> FileID? {
        engine.currentSnapshot().files.first { $0.path == path }?.id
    }

    @Test("Files that always change together are strongly coupled")
    func stronglyCoupled() throws {
        let engine = self.engine(at: 13)
        let view = try #require(id(of: "src/view.swift", in: engine))

        let links = engine.coupling(for: view)
        let viewModel = try #require(links.first { $0.path == "src/viewModel.swift" })
        #expect(viewModel.sharedCommits == 6)
        // The view changed in 8 commits; 6 of them also touched the view model.
        #expect(viewModel.percentage == 75)
    }

    @Test("Unrelated files are not reported")
    func unrelated() throws {
        let engine = self.engine(at: 13)
        let view = try #require(id(of: "src/view.swift", in: engine))
        #expect(!engine.coupling(for: view).contains { $0.path == "src/loner.swift" })
    }

    @Test("A pairing too rare to mean anything is filtered out")
    func belowThreshold() throws {
        let engine = self.engine(at: 13)
        let view = try #require(id(of: "src/view.swift", in: engine))

        // helper.swift shares only 2 commits, under the default minimum of 3.
        #expect(!engine.coupling(for: view).contains { $0.path == "src/helper.swift" })

        let permissive = engine.coupling(for: view, options: CouplingOptions(minimumSharedCommits: 2))
        #expect(permissive.contains { $0.path == "src/helper.swift" })
    }

    /// A commit that rewrites everything says nothing about which files belong together.
    @Test("Sweeping commits do not couple the whole repository")
    func sweepingCommitIgnored() throws {
        let sweep = HistoryFixture.commit("sweep", (0..<40).map {
            HistoryFixture.modified("src/file\($0).swift", added: 1, removed: 1)
        })
        let history = RepositoryHistory(name: "fixture", commits: [
            HistoryFixture.commit("c0", (0..<40).map { HistoryFixture.added("src/file\($0).swift", 10) }),
            sweep, sweep, sweep, sweep,
        ])
        var engine = SnapshotEngine(history: history)
        engine.move(to: 4)

        let first = try #require(engine.currentSnapshot().files.first { $0.path == "src/file0.swift" })
        #expect(engine.coupling(for: first.id).isEmpty)

        // Raising the cap above the commit size brings the (meaningless) links back.
        let permissive = engine.coupling(
            for: first.id, options: CouplingOptions(maximumFilesPerCommit: 100)
        )
        #expect(!permissive.isEmpty)
    }

    @Test("Coupling reflects the scrub position, not the whole history")
    func respectsScrubPosition() throws {
        // At commit 2 the pair has only shared 3 commits so far.
        let engine = self.engine(at: 2)
        let view = try #require(id(of: "src/view.swift", in: engine))
        let link = try #require(engine.coupling(for: view).first)
        #expect(link.sharedCommits == 3)
        #expect(link.percentage == 100)
    }

    @Test("Deleted partners drop out of the results")
    func deletedPartner() throws {
        let history = RepositoryHistory(name: "fixture", commits: [
            HistoryFixture.commit("c0", [
                HistoryFixture.added("a.swift", 10), HistoryFixture.added("b.swift", 10),
            ]),
            HistoryFixture.commit("c1", [
                HistoryFixture.modified("a.swift", added: 1, removed: 1),
                HistoryFixture.modified("b.swift", added: 1, removed: 1),
            ]),
            HistoryFixture.commit("c2", [
                HistoryFixture.modified("a.swift", added: 1, removed: 1),
                HistoryFixture.modified("b.swift", added: 1, removed: 1),
            ]),
            HistoryFixture.commit("c3", [HistoryFixture.deleted("b.swift", lines: 12)]),
        ])
        var engine = SnapshotEngine(history: history)

        engine.move(to: 2)
        let a = try #require(engine.currentSnapshot().files.first { $0.path == "a.swift" })
        #expect(engine.coupling(for: a.id).contains { $0.path == "b.swift" })

        engine.move(to: 3)
        #expect(engine.coupling(for: a.id).isEmpty)
    }

    // MARK: - Whole-snapshot clusters

    @Test("Files that always change together end up in one cluster")
    func clustersFormFromPairs() throws {
        let engine = self.engine(at: 13)
        let report = engine.couplingClusters()
        let view = try #require(id(of: "src/view.swift", in: engine))
        let viewModel = try #require(id(of: "src/viewModel.swift", in: engine))
        let loner = try #require(id(of: "src/loner.swift", in: engine))

        let cluster = try #require(report.clusters.first { $0.files.contains(view) })
        #expect(cluster.files.contains(viewModel))
        // A file that only ever changes alone belongs to nothing.
        #expect(!report.clusters.contains { $0.files.contains(loner) })
    }

    /// A file touched in nearly every commit would look coupled to everything if the degree
    /// were measured against the busier of the pair. What it is, is busy.
    @Test("Coupling is measured against the rarer of the two files")
    func degreeUsesTheRarerFile() throws {
        var commits: [Commit] = []
        // `rare.swift` is touched four times, and never without `busy.swift`.
        for index in 0..<4 {
            commits.append(HistoryFixture.commit("both\(index)", [
                HistoryFixture.modified("src/busy.swift", added: 2, removed: 1),
                HistoryFixture.modified("src/rare.swift", added: 1, removed: 1),
            ]))
        }
        // `busy.swift` is touched sixteen more times on its own.
        for index in 0..<16 {
            commits.append(HistoryFixture.commit("busy\(index)", [
                HistoryFixture.modified("src/busy.swift", added: 3, removed: 1),
            ]))
        }
        var engine = SnapshotEngine(history: RepositoryHistory(name: "rare", commits: commits))
        engine.move(to: 19)
        let report = engine.couplingClusters()

        let pair = try #require(report.clusters.first?.pairs.first)
        #expect(pair.sharedCommits == 4)
        // Every time rare.swift changed, busy.swift changed too — which is the fact worth
        // drawing. Measured the other way round it would be 4 of 20 and vanish.
        #expect(pair.degree == 1)
    }

    @Test("A pair that has shared only a commit or two has demonstrated nothing")
    func weakPairsAreDropped() throws {
        let engine = self.engine(at: 13)
        let report = engine.couplingClusters()
        let helper = try #require(id(of: "src/helper.swift", in: engine))

        // helper.swift and view.swift share exactly two commits, under the minimum.
        #expect(!report.clusters.contains { $0.files.contains(helper) })
    }

    @Test("Sweeping commits do not couple the whole repository into one cluster")
    func sweepsAreIgnoredForClusters() {
        var commits: [Commit] = []
        for index in 0..<4 {
            commits.append(HistoryFixture.commit("sweep\(index)",
                (0..<30).map { HistoryFixture.modified("src/f\($0).swift", added: 1, removed: 1) }
            ))
        }
        var engine = SnapshotEngine(history: RepositoryHistory(name: "sweeps", commits: commits))
        engine.move(to: 3)
        let report = engine.couplingClusters()

        #expect(report.clusters.isEmpty)
        #expect(report.consideredCommits == 0)
        #expect(report.ignoredCommits == 4)
    }

    /// The same guarantee the rest of the engine gives: arriving at a position from either
    /// direction has to produce the same answer.
    @Test("Scrubbing back to a position restores the clusters it had")
    func clustersSurviveScrubbingBackwards() {
        var forward = SnapshotEngine(history: history)
        forward.move(to: 7)
        let expected = forward.couplingClusters()

        var wandered = SnapshotEngine(history: history)
        wandered.move(to: 13)
        wandered.move(to: 7)
        let actual = wandered.couplingClusters()

        #expect(actual.clusters.count == expected.clusters.count)
        #expect(actual.clusters.map(\.files) == expected.clusters.map(\.files))
        #expect(actual.clusters.map(\.strength) == expected.clusters.map(\.strength))
    }

    @Test("An empty repository reports nothing rather than failing")
    func emptyHistoryHasNoClusters() {
        var engine = SnapshotEngine(history: history)
        engine.move(to: -1)
        #expect(engine.couplingClusters().clusters.isEmpty)
    }
}
