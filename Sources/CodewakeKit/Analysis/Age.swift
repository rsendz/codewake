//
//  Age.swift
//  codewake
//
//  Created by Luis Resendez on 19/03/2026.
//

import Foundation

/// How long a file has gone untouched, as of the playhead.
public struct FileAge: Sendable, Identifiable, Hashable {
    public let id: FileID
    public let path: String
    public let lines: Int
    /// Commit that last touched it, and when that was.
    public let lastTouchedIndex: Int
    public let lastTouched: Date
    /// Seconds between that commit and the playhead.
    public let age: TimeInterval
    /// Age as a share of how long the repository had existed by then: 0 for a file touched
    /// at the playhead, 1 for one untouched since the first commit.
    public let share: Double
}

/// One top-level directory, aged.
public struct DirectoryAge: Sendable, Identifiable, Hashable {
    public let name: String
    public let files: Int
    public let lines: Int
    /// Median age of the lines in it, which one enormous stale file cannot skew.
    public let medianAge: TimeInterval

    public var id: String { name }
}

/// Where the codebase is still moving and where it stopped.
public struct AgeReport: Sendable {
    public let commitIndex: Int
    /// The playhead's date — what every age is measured back from.
    public let now: Date
    /// How long the repository had existed at that point.
    public let span: TimeInterval
    /// Largest first, so the map draws the same rectangles as the other views.
    public let files: [FileAge]
    public let directories: [DirectoryAge]
    public let totalLines: Int
    public let medianAge: TimeInterval
    /// Files and lines nobody has touched in a year.
    public let dormantFiles: Int
    public let dormantLines: Int

    public static let dormantAfter: TimeInterval = 365 * 24 * 60 * 60

    public static let empty = AgeReport(
        commitIndex: -1, now: Date(), span: 1, files: [], directories: [],
        totalLines: 0, medianAge: 0, dormantFiles: 0, dormantLines: 0
    )

    public func age(of id: FileID) -> FileAge? {
        files.first { $0.id == id }
    }
}
