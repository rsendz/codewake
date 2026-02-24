//
//  RepositoryHistory.swift
//  codewake
//
//  Created by Luis Resendez on 16/02/2026.
//

import Foundation

/// Stable identity for a file across its whole history, including renames.
public typealias FileID = Int

/// One touch of one file, flattened out of its commit.
public struct FileEvent: Sendable, Hashable {
    public let commitIndex: Int
    public let insertions: Int
    public let deletions: Int
    public let isDeletion: Bool
    /// Post-image blob SHA; nil when the event deleted the file or the blob is unknown.
    public let blobSHA: String?

    public var churn: Int { insertions + deletions }
}

/// The path a file carried starting at a given commit.
public struct PathSpan: Sendable, Hashable {
    public let fromCommitIndex: Int
    public let path: String
}

/// Everything that happened to one file, oldest first.
public struct FileTimeline: Sendable, Identifiable {
    public let id: FileID
    public fileprivate(set) var events: [FileEvent]
    public fileprivate(set) var pathSpans: [PathSpan]

    /// The path this file had as of `commitIndex`, or its first known path if it did not
    /// exist yet.
    public func path(at commitIndex: Int) -> String {
        var result = pathSpans[0].path
        for span in pathSpans {
            if span.fromCommitIndex > commitIndex { break }
            result = span.path
        }
        return result
    }

    public var latestPath: String { pathSpans[pathSpans.count - 1].path }
    public var wasRenamed: Bool { pathSpans.count > 1 }
}

/// A repository's commits plus the per-file timelines derived from them.
public struct RepositoryHistory: Sendable {
    public let name: String
    /// Oldest first. Index into this array is the timeline position everything else uses.
    public let commits: [Commit]
    public let files: [FileTimeline]
    /// For each commit, the files it touched, in the same order as `commits[i].changes`.
    public let touchedFiles: [[FileID]]

    public var commitCount: Int { commits.count }
    public var dateRange: ClosedRange<Date> { commits[0].date...commits[commits.count - 1].date }

    public func file(_ id: FileID) -> FileTimeline { files[id] }

    /// Resolves file identity across renames and flattens commits into per-file timelines.
    ///
    /// A rename carries the existing identity to the new path. A path that is deleted keeps
    /// its identity, so a file resurrected at the same path continues its old timeline
    /// rather than starting a second one. Files the filter rejects are dropped here, so
    /// nothing downstream has to keep re-deciding whether a lock file counts.
    public init(name: String, commits: [Commit], filter: FileFilter = .default) {
        self.name = name
        self.commits = commits

        var files: [FileTimeline] = []
        var touched: [[FileID]] = []
        touched.reserveCapacity(commits.count)
        var idByPath: [String: FileID] = [:]

        func makeFile(path: String, commitIndex: Int) -> FileID {
            let id = files.count
            files.append(FileTimeline(
                id: id,
                events: [],
                pathSpans: [PathSpan(fromCommitIndex: commitIndex, path: path)]
            ))
            idByPath[path] = id
            return id
        }

        for (commitIndex, commit) in commits.enumerated() {
            var idsInCommit: [FileID] = []
            idsInCommit.reserveCapacity(commit.changes.count)

            for change in commit.changes where filter.includes(change.path) {
                let id: FileID
                if case .renamed(let oldPath) = change.kind, let existing = idByPath.removeValue(forKey: oldPath) {
                    id = existing
                    files[id].pathSpans.append(
                        PathSpan(fromCommitIndex: commitIndex, path: change.path)
                    )
                    idByPath[change.path] = id
                } else if let existing = idByPath[change.path] {
                    id = existing
                } else {
                    // Either a genuine add, or a file whose creation predates the history
                    // we were given (shallow clone, or a rename source we never saw).
                    id = makeFile(path: change.path, commitIndex: commitIndex)
                }

                files[id].events.append(FileEvent(
                    commitIndex: commitIndex,
                    insertions: change.isBinary ? 0 : change.insertions,
                    deletions: change.isBinary ? 0 : change.deletions,
                    isDeletion: change.isDeletion,
                    blobSHA: change.blobSHA
                ))
                idsInCommit.append(id)
            }
            touched.append(idsInCommit)
        }

        self.files = files
        self.touchedFiles = touched
    }
}
