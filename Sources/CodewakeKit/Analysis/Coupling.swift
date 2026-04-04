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
