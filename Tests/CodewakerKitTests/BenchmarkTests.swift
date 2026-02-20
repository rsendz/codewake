//
//  BenchmarkTests.swift
//  codewake
//
//  Created by Luis Resendez on 20/02/2026.
//

import Foundation
import Testing

@testable import CodewakerKit

/// Measures the engine against a real repository. Skipped unless `CODEWAKER_BENCH_REPO`
/// points at one, so a checkout with no large repository to hand still runs green:
///
///     CODEWAKER_BENCH_REPO=~/some/repo swift test --filter Benchmarks
@Suite("Benchmarks", .serialized)
struct BenchmarkTests {
    private var repositoryURL: URL? {
        ProcessInfo.processInfo.environment["CODEWAKER_BENCH_REPO"]
            .map { URL(filePath: NSString(string: $0).expandingTildeInPath) }
    }

    private func seconds(_ body: () async throws -> Void) async rethrows -> Double {
        let start = ContinuousClock.now
        try await body()
        return Double(start.duration(to: .now).components.attoseconds) / 1e18
            + Double(start.duration(to: .now).components.seconds)
    }

    @Test("Loads and scrubs a real repository within budget")
    func realRepository() async throws {
        guard let url = repositoryURL else { return }

        var engine: AnalysisEngine?
        let loadTime = await seconds {
            engine = try? await AnalysisEngine.load(from: GitCLIHistoryProvider(repositoryURL: url))
        }
        let loaded = try #require(engine)
        let commits = loaded.summary.commitCount
        print("load: \(commits) commits, \(loaded.summary.fileCount) files in \(loadTime.formatted(.number.precision(.fractionLength(2))))s")

        // Simulates a drag across the whole history: the cached path must stay well under
        // a frame per step or scrubbing will visibly stutter.
        let steps = min(commits, 400)
        let scrubTime = await seconds {
            for step in 0..<steps {
                _ = await loaded.scrub(to: step * commits / steps)
            }
        }
        let perStep = scrubTime / Double(steps) * 1000
        print("scrub: \(perStep.formatted(.number.precision(.fractionLength(2))))ms per step")
        #expect(perStep < 16, "scrubbing must keep up with a 60fps drag")

        let refineTime = await seconds { _ = try? await loaded.refine(at: commits - 1) }
        print("first refine at HEAD: \(refineTime.formatted(.number.precision(.fractionLength(2))))s")

        // Second refine is served entirely from the blob-SHA cache.
        let cachedRefine = await seconds { _ = try? await loaded.refine(at: commits - 1) }
        print("cached refine: \((cachedRefine * 1000).formatted(.number.precision(.fractionLength(2))))ms")
        #expect(cachedRefine < refineTime)
    }
}
