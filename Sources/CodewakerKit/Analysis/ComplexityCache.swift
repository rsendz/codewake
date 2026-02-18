//
//  ComplexityCache.swift
//  codewake
//
//  Created by Luis Resendez on 18/02/2026.
//

import Foundation

/// Complexity scores keyed by blob SHA.
///
/// A blob SHA identifies exact file contents, so a file that did not change between two
/// scrub positions — the overwhelming majority of files, most of the time — is never
/// analyzed twice, no matter how often the user drags across it.
///
/// Purely a store: it never performs I/O, which keeps it synchronous and lets
/// `AnalysisEngine` read it on the drag path without suspending.
final class ComplexityCache {
    private var scores: [String: ComplexityScore] = [:]
    /// Blobs git could not return, or that were skipped as binary or oversized. Remembering
    /// these stops us re-requesting them on every pass.
    private var unavailable: Set<String> = []

    var count: Int { scores.count }

    /// Whatever is already known, with no I/O. Used while the user is dragging.
    func cachedScores(for shas: [String]) -> [String: ComplexityScore] {
        shas.reduce(into: [:]) { result, sha in
            if let score = scores[sha] { result[sha] = score }
        }
    }

    /// SHAs that are neither scored nor known to be unavailable — the set worth fetching.
    func unknownSHAs(among shas: [String]) -> [String] {
        var seen: Set<String> = []
        return shas.filter { sha in
            scores[sha] == nil && !unavailable.contains(sha) && seen.insert(sha).inserted
        }
    }

    /// Scores the blobs that came back and records the rest as unavailable, so a blob git
    /// declined to hand over is not asked for again.
    func store(blobs: [String: String], requested: [String]) {
        for sha in requested {
            if let contents = blobs[sha] {
                scores[sha] = IndentationComplexity.analyze(contents)
            } else {
                unavailable.insert(sha)
            }
        }
    }
}
