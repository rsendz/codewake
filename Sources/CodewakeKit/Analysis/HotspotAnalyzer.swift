//
//  HotspotAnalyzer.swift
//  codewake
//
//  Created by Luis Resendez on 20/02/2026.
//

import Foundation

/// A file scored for how risky it is to touch right now.
public struct Hotspot: Sendable, Identifiable, Hashable {
    public let file: FileSnapshot
    public let complexity: ComplexityScore?
    /// 0...1. Churn and complexity, each normalised against the rest of the snapshot.
    public let score: Double
    public let normalizedChurn: Double
    public let normalizedComplexity: Double
    /// True while complexity is standing in with a size estimate because the blob has not
    /// been read yet — the score is still directionally right, just provisional.
    public let isEstimated: Bool

    public var id: FileID { file.id }
    public var path: String { file.path }
}

/// Scores hotspots as churn × complexity.
///
/// Both inputs are normalised on a log scale before multiplying. Churn and file size are
/// both heavy-tailed — one vendored megafile or one mass-reformat commit would otherwise
/// flatten every other file to the bottom of the colour ramp and make the view useless.
public enum HotspotAnalyzer {
    public static func analyze(
        files: [FileSnapshot],
        complexity: [String: ComplexityScore]
    ) -> [Hotspot] {
        guard !files.isEmpty else { return [] }

        func complexityValue(for file: FileSnapshot) -> (value: Double, score: ComplexityScore?, estimated: Bool) {
            if let sha = file.blobSHA, let score = complexity[sha] {
                return (score.total, score, false)
            }
            // Size stands in until the blob is read, so the first paint of a scrub is
            // immediate and merely refines rather than appearing from nothing.
            return (Double(file.approximateLines), nil, true)
        }

        let measured = files.map { (file: $0, complexity: complexityValue(for: $0)) }
        let maxChurn = measured.map { Double($0.file.churn) }.max() ?? 0
        let maxComplexity = measured.map { $0.complexity.value }.max() ?? 0

        return measured.map { entry in
            let churn = normalize(Double(entry.file.churn), max: maxChurn)
            let complexity = normalize(entry.complexity.value, max: maxComplexity)
            return Hotspot(
                file: entry.file,
                complexity: entry.complexity.score,
                score: churn * complexity,
                normalizedChurn: churn,
                normalizedComplexity: complexity,
                isEstimated: entry.complexity.estimated
            )
        }
        .sorted { $0.score > $1.score }
    }

    private static func normalize(_ value: Double, max maximum: Double) -> Double {
        guard maximum > 0, value > 0 else { return 0 }
        return log1p(value) / log1p(maximum)
    }
}
