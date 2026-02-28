//
//  BranchTests.swift
//  codewake
//
//  Created by Luis Resendez on 28/02/2026.
//

import Foundation
import Testing

@testable import CodewakeKit

@Suite("Branch extraction")
struct BranchTests {
    private func node(
        _ sha: String, parents: [String], day: Int, author: String = "Ada", subject: String = "work"
    ) -> CommitNode {
        CommitNode(
            sha: sha, parents: parents,
            date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            authorName: author, subject: subject
        )
    }

    /// Trunk: root → a → M → d.  Topic branch b → c merged at M.
    private var graph: [CommitNode] {
        [
            node("d", parents: ["M"], day: 6),
            node("M", parents: ["a", "c"], day: 5, subject: "Merge pull request #7 from org/feature/login"),
            node("c", parents: ["b"], day: 4, author: "Grace"),
            node("b", parents: ["a"], day: 3, author: "Grace"),
            node("a", parents: ["root"], day: 2),
            node("root", parents: [], day: 1),
        ]
    }

    @Test("Finds the work that happened off the trunk")
    func findsBranch() throws {
        let branches = BranchExtractor.branches(from: graph)
        #expect(branches.count == 1)

        let branch = try #require(branches.first)
        #expect(branch.name == "feature/login")
        #expect(branch.commitCount == 2)                          // b and c, not the merge
        #expect(branch.startDate == Date(timeIntervalSince1970: 3 * 86_400))
        #expect(branch.mergeDate == Date(timeIntervalSince1970: 5 * 86_400))
        #expect(branch.days == 2)
        #expect(branch.authors.map(\.name) == ["Grace"])
    }

    @Test("Trunk commits are never counted as branch work")
    func excludesTrunk() {
        let branches = BranchExtractor.branches(from: graph)
        #expect(branches[0].commitCount == 2)
        // "a" and "root" are on the first-parent chain and must not be swept in.
    }

    @Test("Churn and timeline position come from the linear history")
    func totals() throws {
        let branches = BranchExtractor.branches(
            from: graph,
            churnBySHA: ["b": (churn: 40, files: 2), "c": (churn: 10, files: 1)],
            timelineIndexBySHA: ["b": 3, "c": 4]
        )
        let branch = try #require(branches.first)
        #expect(branch.churn == 50)
        #expect(branch.filesTouched == 3)
        #expect(branch.timelineIndex == 4)
    }

    @Test("A repository with no merges has no branches")
    func linearHistory() {
        let linear = [
            node("c", parents: ["b"], day: 3),
            node("b", parents: ["a"], day: 2),
            node("a", parents: [], day: 1),
        ]
        #expect(BranchExtractor.branches(from: linear).isEmpty)
        #expect(BranchExtractor.branches(from: []).isEmpty)
    }

    /// A topic branch that merges main back into itself before landing still counts as one
    /// branch, and the trunk commits it absorbed must not be attributed to it.
    @Test("Back-merges from the trunk do not inflate a branch")
    func backMerge() throws {
        let graph = [
            node("M2", parents: ["t2", "f2"], day: 9, subject: "Merge branch 'feature'"),
            node("f2", parents: ["f1", "t2"], day: 8, subject: "Merge remote-tracking branch 'origin/main' into feature"),
            node("t2", parents: ["t1"], day: 7),
            node("f1", parents: ["t1"], day: 6, author: "Grace"),
            node("t1", parents: [], day: 5),
        ]
        let branches = BranchExtractor.branches(from: graph)
        #expect(branches.count == 1)
        let branch = try #require(branches.first)
        #expect(branch.name == "feature")
        #expect(branch.commitCount == 1)  // only f1; f2 is a merge, t1/t2 are trunk
    }

    @Test("Two commits are never attributed to two different branches")
    func noDoubleCounting() {
        let graph = [
            node("M2", parents: ["M1", "y"], day: 8, subject: "Merge branch 'second'"),
            node("M1", parents: ["a", "x"], day: 6, subject: "Merge branch 'first'"),
            node("y", parents: ["M1"], day: 7, author: "Grace"),
            node("x", parents: ["a"], day: 5, author: "Grace"),
            node("a", parents: [], day: 1),
        ]
        let branches = BranchExtractor.branches(from: graph)
        #expect(branches.count == 2)
        #expect(branches.reduce(0) { $0 + $1.commitCount } == 2)
    }

    @Test(
        "Names are recovered from merge subjects",
        arguments: [
            ("Merge pull request #742 from Apantli/personal/luis/addSupabase", "personal/luis/addSupabase"),
            ("Merge pull request #3 from acme/fix-typo", "fix-typo"),
            ("Merge branch 'feature/x'", "feature/x"),
            ("Merge branch 'hotfix' into main", "hotfix"),
            ("Merge remote-tracking branch 'origin/upstream-sync'", "upstream-sync"),
        ]
    )
    func naming(subject: String, expected: String) {
        #expect(BranchExtractor.name(fromMergeSubject: subject, fallback: nil) == expected)
    }

    @Test("An unrecognisable merge message falls back to the branch's first commit")
    func namingFallback() {
        #expect(BranchExtractor.name(fromMergeSubject: "Merged stuff", fallback: "add login form")
            == "add login form")
    }

    private func branch(_ id: Int, start: Int, end: Int, churn: Int = 1) -> Branch {
        Branch(
            id: id, name: "b\(id)", commitCount: 1, churn: churn, filesTouched: 1, authors: [],
            startDate: Date(timeIntervalSince1970: TimeInterval(start) * 86_400),
            mergeDate: Date(timeIntervalSince1970: TimeInterval(end) * 86_400),
            timelineIndex: 0
        )
    }

    @Test("Lanes pack branches so none overlap in time")
    func lanes() throws {
        // Two overlapping branches, then one that starts after both finish.
        let lanes = assignBranchLanes([
            branch(0, start: 1, end: 5),
            branch(1, start: 2, end: 6),
            branch(2, start: 7, end: 8),
        ])
        #expect(lanes[0] != lanes[1])
        #expect(lanes[2] == 0)  // reuses the first lane, which is free again by day 7
    }

    /// With hundreds of branches only the top rows have room for labels, so the ones worth
    /// labelling have to land there.
    @Test("The biggest branches claim the top rows")
    func biggestBranchesGetTopLanes() {
        let lanes = assignBranchLanes([
            branch(0, start: 1, end: 9, churn: 10),
            branch(1, start: 2, end: 8, churn: 5_000),
            branch(2, start: 3, end: 7, churn: 200),
        ])
        #expect(lanes[1] == 0)
        #expect(lanes[2] == 1)
        #expect(lanes[0] == 2)
    }
}
