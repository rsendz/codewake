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
    /// Every non-merge commit, oldest first.
    func loadCommits() async throws -> [Commit]

    /// Contents of the given blobs, keyed by SHA. Missing or unreadable blobs are omitted.
    func loadBlobs(shas: [String]) async throws -> [String: String]

    /// The commit graph, newest first, including merges. Used to recover branch structure,
    /// which the linear commit list deliberately flattens away.
    func loadGraph() async throws -> [CommitNode]

    /// Display name for the repository.
    var name: String { get }
}
