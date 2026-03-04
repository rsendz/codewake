//
//  Ownership.swift
//  codewake
//
//  Created by Luis Resendez on 04/03/2026.
//

import Foundation

/// Who owns one file, as of a point in history.
///
/// Ownership is measured in commits rather than surviving lines. `git blame` would answer
/// "whose lines are these right now", which is a different and more fragile question — a
/// reformat or a rename rewrites every line's author without moving any knowledge. Who
/// keeps coming back to change a file is the durable signal, and it is the one the
/// research on ownership and defect risk uses.
public struct FileOwnership: Sendable, Identifiable, Hashable {
    public let id: FileID
    public let path: String
    public let lines: Int
    /// Commits that have touched this file up to this point.
    public let commits: Int
    public let authorCount: Int
    /// The author with the most commits to this file.
    public let owner: String
    public let ownerCommits: Int

    /// The owner's share of the file's commits, `1/authorCount ... 1`.
    public var share: Double {
        commits > 0 ? Double(ownerCommits) / Double(commits) : 0
    }

    /// True when exactly one person has ever touched this file — the case where losing one
    /// contributor loses the only person who has seen the code.
    public var isSoleAuthored: Bool { authorCount == 1 }
}

/// One author's standing across the whole repository at a point in history.
public struct AuthorOwnership: Sendable, Identifiable, Hashable {
    public let name: String
    /// Files where this author has more commits than anyone else.
    public let ownedFiles: Int
    public let ownedLines: Int
    /// Files nobody else has ever touched.
    public let soleAuthoredFiles: Int
    public let soleAuthoredLines: Int
    /// Files this author has touched at all, owned or not.
    public let touchedFiles: Int

    public var id: String { name }
}

/// Repository-wide ownership at a point in history.
public struct OwnershipReport: Sendable {
    public let commitIndex: Int
    /// Every live file, largest first, so the treemap can take a prefix and know it is
    /// dropping only slivers.
    public let files: [FileOwnership]
    /// Every author who owns something, by how much of the codebase they own.
    public let authors: [AuthorOwnership]
    public let totalFiles: Int
    public let totalLines: Int
    public let soleAuthoredFiles: Int
    public let soleAuthoredLines: Int
    /// Fewest owners whose files together make up half the codebase — the number of people
    /// who would have to disappear before half of it belongs to nobody who remains.
    ///
    /// A truck-factor approximation, in the sense of Avelino et al.: coverage by dominant
    /// authorship rather than a reachability argument over the whole team.
    public let busFactor: Int

    private let indexByFile: [FileID: Int]

    init(
        commitIndex: Int,
        files: [FileOwnership],
        authors: [AuthorOwnership],
        totalFiles: Int,
        totalLines: Int,
        soleAuthoredFiles: Int,
        soleAuthoredLines: Int,
        busFactor: Int
    ) {
        self.commitIndex = commitIndex
        self.files = files
        self.authors = authors
        self.totalFiles = totalFiles
        self.totalLines = totalLines
        self.soleAuthoredFiles = soleAuthoredFiles
        self.soleAuthoredLines = soleAuthoredLines
        self.busFactor = busFactor
        self.indexByFile = Dictionary(
            uniqueKeysWithValues: files.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    public static let empty = OwnershipReport(
        commitIndex: -1, files: [], authors: [],
        totalFiles: 0, totalLines: 0,
        soleAuthoredFiles: 0, soleAuthoredLines: 0, busFactor: 0
    )

    public func ownership(of id: FileID) -> FileOwnership? {
        indexByFile[id].map { files[$0] }
    }

    /// Share of the codebase, by lines, that only one person has ever touched.
    public var soleAuthoredLineShare: Double {
        totalLines > 0 ? Double(soleAuthoredLines) / Double(totalLines) : 0
    }
}
