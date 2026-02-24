//
//  FileChange.swift
//  codewake
//
//  Created by Luis Resendez on 16/02/2026.
//

import Foundation

/// How a single file was touched by one commit.
public struct FileChange: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case added
        case modified
        case deleted
        case renamed(from: String)
    }

    /// Path as of this commit. For a rename this is the new path.
    public let path: String
    public let insertions: Int
    public let deletions: Int
    public let kind: Kind

    /// Binary files report `-` for both counts in numstat; the change still exists but scores no line churn.
    public let isBinary: Bool

    /// Post-image blob SHA, straight from `git log --raw`. Nil for deletions.
    /// Having this per event means the blob for any file at any point in history is
    /// available without a tree lookup.
    public let blobSHA: String?

    public init(
        path: String,
        insertions: Int,
        deletions: Int,
        kind: Kind,
        isBinary: Bool = false,
        blobSHA: String? = nil
    ) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.kind = kind
        self.isBinary = isBinary
        self.blobSHA = blobSHA
    }

    public var churn: Int { insertions + deletions }

    public var previousPath: String? {
        if case .renamed(let from) = kind { return from }
        return nil
    }

    public var isDeletion: Bool { kind == .deleted }
}
