//
//  Coupling.swift
//  codewake
//
//  Created by Luis Resendez on 25/02/2026.
//

import Foundation

/// Another file that tends to change in the same commits as the one being inspected.
public struct CouplingLink: Sendable, Identifiable, Hashable {
    public let id: FileID
    public let path: String
    /// Commits that touched both files.
    public let sharedCommits: Int
    /// Commits that touched the partner at all, up to this point in history.
    public let partnerCommits: Int
    /// Share of the *selected* file's commits that also touched the partner, so the number
    /// reads directionally: "when I change this file, I change that one X% of the time."
    public let degree: Double

    public var percentage: Int { Int((degree * 100).rounded()) }
}

public struct CouplingOptions: Sendable {
    /// Commits touching more files than this are ignored. A mass rename, a formatting
    /// sweep, or an initial import couples every file to every other file and means
    /// nothing; including them drowns the real signal.
    public var maximumFilesPerCommit: Int
    /// Two files that have shared one or two commits have not demonstrated anything.
    public var minimumSharedCommits: Int
    public var limit: Int

    public init(maximumFilesPerCommit: Int = 25, minimumSharedCommits: Int = 3, limit: Int = 8) {
        self.maximumFilesPerCommit = maximumFilesPerCommit
        self.minimumSharedCommits = minimumSharedCommits
        self.limit = limit
    }

    public static let `default` = CouplingOptions()
}

/// Two files that keep changing in the same commits.
public struct CouplingPair: Sendable, Hashable {
    public let a: FileID
    public let b: FileID
    public let sharedCommits: Int
    /// The stronger of the two directions: when the file that changes less often changes,
    /// how much of the time the other one changes too.
    ///
    /// Symmetric on purpose. The inspector's per-file view asks a directional question —
    /// "when I touch this, what else do I touch" — because it has a file in hand. A map of
    /// the whole snapshot has no such anchor, and an edge that means different things
    /// depending on which end you read it from cannot be drawn.
    public let degree: Double
}

/// A group of files that all change together, directly or through each other.
public struct CouplingCluster: Sendable, Identifiable {
    public let id: Int
    /// Busiest first.
    public let files: [FileID]
    public let pairs: [CouplingPair]
    /// The tightest pair in it, which is what the cluster is ranked by.
    public let strength: Double
}

public struct CouplingReport: Sendable {
    public let commitIndex: Int
    public let clusters: [CouplingCluster]
    public let paths: [FileID: String]
    /// Commits counted per file, after the sweeping ones were discarded.
    public let commitCounts: [FileID: Int]
    public let consideredCommits: Int
    /// Commits touching too many files to mean anything, and so left out.
    public let ignoredCommits: Int

    public static let empty = CouplingReport(
        commitIndex: -1, clusters: [], paths: [:], commitCounts: [:],
        consideredCommits: 0, ignoredCommits: 0
    )

    public func path(_ id: FileID) -> String { paths[id] ?? "" }
}

public struct CouplingClusterOptions: Sendable {
    /// Same rule as the per-file question: a commit touching more files than this couples
    /// everything to everything and means nothing.
    public var maximumFilesPerCommit: Int
    public var minimumSharedCommits: Int
    /// Below this the pair is a coincidence, not a relationship, and drawing it turns the
    /// map into a hairball.
    public var minimumDegree: Double
    public var maximumPairs: Int
    public var maximumClusters: Int

    public init(
        maximumFilesPerCommit: Int = 25,
        minimumSharedCommits: Int = 3,
        minimumDegree: Double = 0.55,
        maximumPairs: Int = 80,
        // Nine fits a three-by-three grid with room for every file's name beside it. More
        // than that and the rings shrink until the diagram is dots.
        maximumClusters: Int = 9
    ) {
        self.maximumFilesPerCommit = maximumFilesPerCommit
        self.minimumSharedCommits = minimumSharedCommits
        self.minimumDegree = minimumDegree
        self.maximumPairs = maximumPairs
        self.maximumClusters = maximumClusters
    }

    public static let `default` = CouplingClusterOptions()
}
