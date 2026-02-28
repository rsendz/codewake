//
//  Branch.swift
//  codewake
//
//  Created by Luis Resendez on 28/02/2026.
//

import Foundation

/// One commit's place in the graph. Unlike `Commit` this carries no per-file detail — it
/// exists purely to work out the shape of history, so it stays cheap to load for every
/// commit including merges.
public struct CommitNode: Sendable, Hashable {
    public let sha: String
    public let parents: [String]
    public let date: Date
    public let authorName: String
    public let subject: String

    public init(sha: String, parents: [String], date: Date, authorName: String, subject: String) {
        self.sha = sha
        self.parents = parents
        self.date = date
        self.authorName = authorName
        self.subject = subject
    }

    public var isMerge: Bool { parents.count > 1 }
}

/// A line of work that was developed away from the main line and then merged back.
public struct Branch: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    /// Commits made on the branch, excluding the merge commit itself.
    public let commitCount: Int
    public let churn: Int
    public let filesTouched: Int
    public let authors: [AuthorShare]
    /// When its first commit was made.
    public let startDate: Date
    /// When it landed on the main line.
    public let mergeDate: Date
    /// Position in the scrubbable timeline of the branch's last commit, so selecting a
    /// branch can move the playhead to the moment its work had all landed.
    public let timelineIndex: Int

    public var duration: TimeInterval { max(mergeDate.timeIntervalSince(startDate), 0) }

    public var days: Int {
        max(Int((duration / 86_400).rounded()), 0)
    }
}

/// Extracts merged branches from the commit graph.
///
/// The "main line" is the first-parent chain from HEAD — the trunk as git itself sees it.
/// Every merge commit on that trunk brings in one or more other parents, and the commits
/// reachable from those parents but not from the trunk are exactly the work that happened
/// on a branch. Walking it this way needs no ref names (topic branches are usually deleted
/// after merging) and no `git rev-list` call per merge.
public enum BranchExtractor {
    public static func branches(
        from nodes: [CommitNode],
        churnBySHA: [String: (churn: Int, files: Int)] = [:],
        timelineIndexBySHA: [String: Int] = [:]
    ) -> [Branch] {
        guard let head = nodes.first else { return [] }
        let bySHA = Dictionary(nodes.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })

        // The trunk, newest first.
        var mainline: [String] = []
        var mainlineSet: Set<String> = []
        var cursor: String? = head.sha
        while let sha = cursor, let node = bySHA[sha], mainlineSet.insert(sha).inserted {
            mainline.append(sha)
            cursor = node.parents.first
        }

        var claimed: Set<String> = []
        var branches: [Branch] = []

        // Oldest merge first, so when a commit could belong to two merges the earlier one
        // keeps it rather than a later merge re-counting the same work.
        for sha in mainline.reversed() {
            guard let merge = bySHA[sha], merge.isMerge else { continue }

            for parent in merge.parents.dropFirst() {
                let members = walk(from: parent, bySHA: bySHA, stoppingAt: mainlineSet, claimed: &claimed)
                guard !members.isEmpty else { continue }

                let commits = members.compactMap { bySHA[$0] }
                let totals = commits.reduce(into: (churn: 0, files: 0)) { totals, node in
                    let counts = churnBySHA[node.sha] ?? (0, 0)
                    totals.churn += counts.churn
                    totals.files += counts.files
                }

                var authorCounts: [String: Int] = [:]
                for commit in commits where !commit.isMerge {
                    authorCounts[commit.authorName, default: 0] += 1
                }

                branches.append(Branch(
                    id: branches.count,
                    name: name(fromMergeSubject: merge.subject, fallback: commits.min { $0.date < $1.date }?.subject),
                    commitCount: commits.count { !$0.isMerge },
                    churn: totals.churn,
                    filesTouched: totals.files,
                    authors: authorCounts
                        .map { AuthorShare(name: $0.key, commits: $0.value) }
                        .sorted { ($0.commits, $1.name) > ($1.commits, $0.name) },
                    startDate: commits.map(\.date).min() ?? merge.date,
                    mergeDate: merge.date,
                    timelineIndex: members.compactMap { timelineIndexBySHA[$0] }.max() ?? 0
                ))
            }
        }
        return branches
    }

    /// Collects everything reachable from `start` that is not on the trunk and has not
    /// already been attributed to an earlier branch.
    private static func walk(
        from start: String,
        bySHA: [String: CommitNode],
        stoppingAt mainline: Set<String>,
        claimed: inout Set<String>
    ) -> [String] {
        guard !mainline.contains(start), !claimed.contains(start) else { return [] }

        var found: [String] = []
        var queue = [start]
        while let sha = queue.popLast() {
            guard !mainline.contains(sha), claimed.insert(sha).inserted, let node = bySHA[sha] else {
                continue
            }
            found.append(sha)
            queue.append(contentsOf: node.parents)
        }
        return found
    }

    /// Recovers a readable name from the merge commit's subject. Topic branches are
    /// normally deleted once merged, so their names survive only in the message git wrote.
    static func name(fromMergeSubject subject: String, fallback: String?) -> String {
        if let range = subject.range(of: "Merge pull request #"),
           let from = subject.range(of: " from ", range: range.upperBound..<subject.endIndex) {
            let reference = subject[from.upperBound...].trimmingCharacters(in: .whitespaces)
            // "org/team/feature" — the first component is the fork owner, not the branch.
            return reference.split(separator: "/").dropFirst().joined(separator: "/")
                .ifEmpty(reference)
        }
        if let open = subject.firstIndex(of: "'"),
           let close = subject[subject.index(after: open)...].firstIndex(of: "'") {
            let reference = String(subject[subject.index(after: open)..<close])
            return reference.hasPrefix("origin/") ? String(reference.dropFirst(7)) : reference
        }
        return fallback.map { String($0.prefix(60)) } ?? "merged work"
    }
}

extension String {
    fileprivate func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}

/// Packs branches into rows so none overlap in time, the way a Gantt chart does.
///
/// Rows are claimed by the biggest branches first, so the work that moved the most code
/// settles into the top rows where there is room to label it, and the swarm of one-day
/// branches fills in below. Ordering by start date instead would scatter the few branches
/// worth reading among hundreds of slivers.
public func assignBranchLanes(_ branches: [Branch], padding: TimeInterval = 0) -> [Branch.ID: Int] {
    var laneEnds: [Date] = []
    var lanes: [Branch.ID: Int] = [:]

    for branch in branches.sorted(by: { ($0.churn, $1.startDate) > ($1.churn, $0.startDate) }) {
        let lane = laneEnds.firstIndex { $0 <= branch.startDate } ?? laneEnds.count
        if lane == laneEnds.count {
            laneEnds.append(branch.mergeDate.addingTimeInterval(padding))
        } else {
            laneEnds[lane] = branch.mergeDate.addingTimeInterval(padding)
        }
        lanes[branch.id] = lane
    }
    return lanes
}
