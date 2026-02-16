//
//  Commit.swift
//  codewake
//
//  Created by Luis Resendez on 16/02/2026.
//

import Foundation

public struct Commit: Sendable, Identifiable {
    public let sha: String
    public let authorName: String
    public let authorEmail: String
    public let date: Date
    public let subject: String
    public let changes: [FileChange]

    public var id: String { sha }

    public init(
        sha: String,
        authorName: String,
        authorEmail: String,
        date: Date,
        subject: String,
        changes: [FileChange]
    ) {
        self.sha = sha
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.subject = subject
        self.changes = changes
    }

    public var shortSHA: String { String(sha.prefix(7)) }
    public var totalChurn: Int { changes.reduce(0) { $0 + $1.churn } }
}
