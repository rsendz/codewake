//
//  TimelineSnapshot.swift
//  codewake
//
//  Created by Luis Resendez on 20/02/2026.
//

import Foundation

/// One file as it stood at a particular point in history.
public struct FileSnapshot: Sendable, Identifiable, Hashable {
    public let id: FileID
    public let path: String
    /// Lines added plus removed across every commit up to this point.
    public let churn: Int
    public let commitCount: Int
    /// Running `insertions - deletions`, which tracks real line count closely enough for
    /// sizing a treemap and costs nothing beyond the log we already parsed.
    public let approximateLines: Int
    /// Blob at this point in history, for on-demand complexity analysis.
    public let blobSHA: String?
}

/// The whole repository as it stood at a particular commit.
public struct TimelineSnapshot: Sendable {
    /// Index into `RepositoryHistory.commits`; -1 means "before the first commit".
    public let commitIndex: Int
    public let files: [FileSnapshot]

    public var totalChurn: Int { files.reduce(0) { $0 + $1.churn } }
    public var totalLines: Int { files.reduce(0) { $0 + $1.approximateLines } }
    public var fileCount: Int { files.count }
}
