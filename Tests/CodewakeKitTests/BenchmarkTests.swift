//
//  BenchmarkTests.swift
//  codewake
//
//  Created by Luis Resendez on 20/02/2026.
//

import CoreGraphics
import Foundation
import Testing

@testable import CodewakeKit

/// Measures the engine against a real repository. Skipped unless `CODEWAKE_BENCH_REPO`
/// points at one, so a checkout with no large repository to hand still runs green:
///
///     CODEWAKE_BENCH_REPO=~/some/repo swift test --filter Benchmarks
@Suite("Benchmarks", .serialized)
struct BenchmarkTests {
    private var repositoryURL: URL? {
        ProcessInfo.processInfo.environment["CODEWAKE_BENCH_REPO"]
            .map { URL(filePath: NSString(string: $0).expandingTildeInPath) }
    }

    /// Real memory charged to this process, which is what a user would see in Activity
    /// Monitor rather than the much larger virtual size.
    private func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    private func megabytes(_ bytes: Int) -> String {
        (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(0))) + " MB"
    }

    private func seconds(_ body: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try body()
        return Double(start.duration(to: .now).components.attoseconds) / 1e18
            + Double(start.duration(to: .now).components.seconds)
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

        // Timed per phase, because on a large repository the wait is long enough that
        // knowing which part of it is slow is the whole point.
        nonisolated(unsafe) var marks: [(LoadPhase, ContinuousClock.Instant)] = []
        var engine: AnalysisEngine?
        let loadTime = await seconds {
            engine = try? await AnalysisEngine.load(from: GitCLIHistoryProvider(repositoryURL: url)) {
                marks.append(($0, .now))
            }
        }
        let loaded = try #require(engine)
        let commits = loaded.summary.commitCount
        print("load: \(commits) commits, \(loaded.summary.fileCount) files in \(loadTime.formatted(.number.precision(.fractionLength(2))))s")
        for (mark, next) in zip(marks, marks.dropFirst()) {
            let elapsed = Double(mark.1.duration(to: next.1).components.seconds)
                + Double(mark.1.duration(to: next.1).components.attoseconds) / 1e18
            print("  \(mark.0): \(elapsed.formatted(.number.precision(.fractionLength(2))))s")
        }

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

        // Ownership walks every live file rather than the top few hundred, so it is the
        // one query whose cost scales with the size of the repository rather than with the
        // size of the view. It runs once when the playhead settles.
        var report: OwnershipReport?
        let ownershipTime = await seconds { report = await loaded.ownership(at: commits - 1) }
        let ownership = try #require(report)
        print("ownership: \(ownership.totalFiles) files, \(ownership.authors.count) authors, bus factor \(ownership.busFactor) in \((ownershipTime * 1000).formatted(.number.precision(.fractionLength(0))))ms")
        #expect(ownershipTime < 2.0, "ownership must not stall the settle after a scrub")

        let cachedOwnership = await seconds { _ = await loaded.ownership(at: commits - 1) }
        print("cached ownership: \((cachedOwnership * 1000).formatted(.number.precision(.fractionLength(2))))ms")

        // Age asks the same shape of question over the same set of files, but reads each
        // file's last applied event instead of walking its history. On a repository whose
        // files have short histories that buys nothing measurable — the per-file work
        // dominates — so this is a ceiling, not a comparison.
        var ageReport: AgeReport?
        let ageTime = await seconds { ageReport = await loaded.ages(at: commits - 2) }
        let ages = try #require(ageReport)
        print("age: \(ages.files.count) files, median \((ages.medianAge / 86_400).formatted(.number.precision(.fractionLength(0))))d, \(ages.dormantFiles) dormant in \((ageTime * 1000).formatted(.number.precision(.fractionLength(2))))ms")
        #expect(ageTime < 1.0, "age must not stall the settle after a scrub")

        // Coupling clusters are the only derived view that builds a table rather than
        // reading one, so this is the one to watch: it runs on every playback step.
        var couplingReport: CouplingReport?
        let couplingTime = await seconds { couplingReport = await loaded.couplingClusters(at: commits - 3) }
        let coupling = try #require(couplingReport)
        print("coupling clusters: \(coupling.clusters.count) clusters over \(coupling.consideredCommits) commits (\(coupling.ignoredCommits) ignored) in \((couplingTime * 1000).formatted(.number.precision(.fractionLength(1))))ms")
        // Playback steps 20 times a second, so anything past this cannot keep up with it.
        #expect(couplingTime < 0.05, "coupling clusters must keep up with playback")

        // The treemap is laid out from scratch on every draw, so it has to be cheap at the
        // size the view actually asks for.
        let hotspots = await loaded.hotspots(at: commits - 1)
        let layoutTime = seconds {
            for _ in 0..<50 {
                _ = TreemapLayout.layout(
                    hotspots: hotspots, in: CGRect(x: 0, y: 0, width: 1200, height: 800)
                )
            }
        }
        print("treemap layout: \(hotspots.count) tiles in \((layoutTime / 50 * 1000).formatted(.number.precision(.fractionLength(2))))ms")
        #expect(layoutTime / 50 < 0.016, "layout must fit inside a frame")

        let refineTime = await seconds { _ = try? await loaded.refine(at: commits - 1) }
        print("first refine at HEAD: \(refineTime.formatted(.number.precision(.fractionLength(2))))s")

        // Second refine is served entirely from the blob-SHA cache.
        let cachedRefine = await seconds { _ = try? await loaded.refine(at: commits - 1) }
        print("cached refine: \((cachedRefine * 1000).formatted(.number.precision(.fractionLength(2))))ms")
        #expect(cachedRefine < refineTime)

        print("memory: \(megabytes(footprintBytes())) resident with the repository loaded")
    }
}
