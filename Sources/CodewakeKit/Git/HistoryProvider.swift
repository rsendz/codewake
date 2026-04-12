//
//  HistoryProvider.swift
//  codewake
//
//  Created by Luis Resendez on 16/02/2026.
//

import Foundation

/// Source of a repository's history. The analysis layer only ever talks to this, so the
/// git CLI can be swapped for another backend without touching anything above it.
public protocol HistoryProvider: Sendable {
    /// How many commits the history has, before reading any of them.
    ///
    /// Cheap enough to ask first: it lets the app say how long the wait will be, and
    /// whether to warn about it, rather than showing an unqualified spinner.
    func commitCount() async throws -> Int

    /// Every non-merge commit, oldest first.
    func loadCommits() async throws -> [Commit]

    /// Contents of the given blobs, keyed by SHA. Missing or unreadable blobs are omitted.
    func loadBlobs(shas: [String]) async throws -> [String: String]

    /// Display name for the repository.
    var name: String { get }
}
