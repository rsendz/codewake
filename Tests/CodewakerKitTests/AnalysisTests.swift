//
//  AnalysisTests.swift
//  codewake
//
//  Created by Luis Resendez on 20/02/2026.
//

import CoreGraphics
import Foundation
import Testing

@testable import CodewakerKit

@Suite("Indentation complexity")
struct IndentationComplexityTests {
    @Test("Nesting costs more than length")
    func nestingDominates() {
        let flat = """
        let a = 1
        let b = 2
        let c = 3
        let d = 4
        """
        let nested = """
        func f() {
            if x {
                while y {
                    doThing()
                }
            }
        }
        """
        #expect(IndentationComplexity.analyze(nested).total > IndentationComplexity.analyze(flat).total)
        #expect(IndentationComplexity.analyze(flat).max == 0)
        #expect(IndentationComplexity.analyze(nested).max == 3)
    }

    /// Without width detection a 2-space file would score half as complex as an identical
    /// 4-space one, making indent style look like an architecture problem.
    @Test("Indent width is inferred, so style does not change the score")
    func indentWidthDetection() {
        let twoSpace = "func f() {\n  if x {\n    go()\n  }\n}"
        let fourSpace = "func f() {\n    if x {\n        go()\n    }\n}"
        #expect(IndentationComplexity.analyze(twoSpace).total == IndentationComplexity.analyze(fourSpace).total)
    }

    @Test("Tabs count as one level each")
    func tabs() {
        let tabbed = "func f() {\n\tif x {\n\t\tgo()\n\t}\n}"
        #expect(IndentationComplexity.analyze(tabbed).max == 2)
    }

    @Test("Blank lines, comments, and lone braces are not logical lines")
    func ignoredLines() {
        let source = """
        func f() {
            // a comment

            go()
        }
        """
        let score = IndentationComplexity.analyze(source)
        #expect(score.logicalLines == 2)  // `func f() {` and `go()`
        #expect(score.total == 1)
    }

    @Test("Empty input scores zero rather than dividing by it")
    func empty() {
        #expect(IndentationComplexity.analyze("") == .zero)
        #expect(IndentationComplexity.analyze("\n\n\n") == .zero)
    }
}

@Suite("Hotspot scoring")
struct HotspotAnalyzerTests {
    private func file(_ id: FileID, path: String, churn: Int, lines: Int, blob: String?) -> FileSnapshot {
        FileSnapshot(
            id: id, path: path, churn: churn, commitCount: 1,
            approximateLines: lines, blobSHA: blob
        )
    }

    @Test("Churn and complexity both have to be high to score high")
    func requiresBoth() throws {
        let files = [
            file(0, path: "hot.swift", churn: 500, lines: 400, blob: "a"),
            file(1, path: "churny-but-simple.swift", churn: 500, lines: 400, blob: "b"),
            file(2, path: "complex-but-still.swift", churn: 2, lines: 400, blob: "c"),
        ]
        let complexity = [
            "a": ComplexityScore(total: 900, mean: 2.2, max: 6, logicalLines: 400),
            "b": ComplexityScore(total: 10, mean: 0.1, max: 1, logicalLines: 400),
            "c": ComplexityScore(total: 900, mean: 2.2, max: 6, logicalLines: 400),
        ]

        let ranked = HotspotAnalyzer.analyze(files: files, complexity: complexity)
        #expect(ranked.first?.path == "hot.swift")
        let simple = try #require(ranked.first { $0.path == "churny-but-simple.swift" })
        let quiet = try #require(ranked.first { $0.path == "complex-but-still.swift" })
        #expect(ranked[0].score > simple.score)
        #expect(ranked[0].score > quiet.score)
    }

    @Test("Files without a scored blob fall back to size and are flagged as estimated")
    func estimatedFallback() throws {
        let files = [file(0, path: "a.swift", churn: 100, lines: 200, blob: "unscored")]
        let ranked = HotspotAnalyzer.analyze(files: files, complexity: [:])
        let hotspot = try #require(ranked.first)
        #expect(hotspot.isEstimated)
        #expect(hotspot.complexity == nil)
    }

    @Test("Scores stay in range and sort descending")
    func bounds() {
        let files = (0..<25).map {
            file($0, path: "f\($0).swift", churn: $0 * 13, lines: $0 * 7 + 1, blob: "b\($0)")
        }
        let ranked = HotspotAnalyzer.analyze(files: files, complexity: [:])
        #expect(ranked.allSatisfy { (0...1).contains($0.score) })
        #expect(ranked == ranked.sorted { $0.score > $1.score })
    }

    @Test("An empty snapshot produces no hotspots rather than dividing by zero")
    func emptyInput() {
        #expect(HotspotAnalyzer.analyze(files: [], complexity: [:]).isEmpty)
    }
}

@Suite("Treemap layout")
struct TreemapLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func hotspots(_ count: Int, directory: String = "src") -> [Hotspot] {
        (0..<count).map { index in
            Hotspot(
                file: FileSnapshot(
                    id: index, path: "\(directory)/file\(index).swift", churn: 100 - index,
                    commitCount: 3, approximateLines: 200 - index * 2, blobSHA: "b\(index)"
                ),
                complexity: nil,
                score: Double(count - index) / Double(count),
                normalizedChurn: 0.5, normalizedComplexity: 0.5, isEstimated: false
            )
        }
    }

    @Test("Rectangles fill their container without overflowing it")
    func fillsBounds() {
        let areas = [50.0, 30, 12, 5, 3]
        let frames = TreemapLayout.squarify(areas, in: bounds)

        let covered = frames.reduce(0) { $0 + Double($1.width * $1.height) }
        #expect(abs(covered - Double(bounds.width * bounds.height)) < 1)
        #expect(frames.allSatisfy { bounds.insetBy(dx: -0.001, dy: -0.001).contains($0) })
    }

    @Test("Rectangles do not overlap")
    func noOverlap() {
        let frames = TreemapLayout.squarify((1...20).map { Double($0 * $0) }, in: bounds)
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                #expect(a.intersection(b).isEmpty || a.intersection(b).width * a.intersection(b).height < 0.001)
            }
        }
    }

    @Test("Area is proportional to value")
    func proportional() {
        let frames = TreemapLayout.squarify([60, 30, 10], in: bounds)
        let total = Double(bounds.width * bounds.height)
        #expect(abs(Double(frames[0].width * frames[0].height) / total - 0.6) < 0.01)
        #expect(abs(Double(frames[2].width * frames[2].height) / total - 0.1) < 0.01)
    }

    /// The point of squarifying rather than slicing: rectangles you can actually click and
    /// read a filename in.
    @Test("Rectangles stay closer to square than a naive slice would")
    func aspectRatios() {
        let frames = TreemapLayout.squarify(Array(repeating: 1.0, count: 16), in: bounds)
        let worst = frames.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? .infinity
        #expect(worst < 3)
    }

    @Test("Files are grouped by top-level directory")
    func grouping() {
        let mixed = hotspots(4, directory: "src") + hotspots(3, directory: "tests")
        let groups = TreemapLayout.layout(hotspots: mixed, in: bounds)
        #expect(Set(groups.map(\.id)) == ["src", "tests"])
    }

    @Test("Too many directories fold into one 'other' group")
    func groupCap() {
        let many = (0..<30).flatMap { hotspots(2, directory: "dir\($0)") }
        let groups = TreemapLayout.layout(hotspots: many, in: bounds)
        #expect(groups.count <= TreemapLayout.maximumGroups)
        #expect(groups.contains { $0.id == TreemapLayout.otherGroupName })
    }

    @Test("Degenerate inputs produce nothing instead of crashing")
    func degenerate() {
        #expect(TreemapLayout.layout(hotspots: [], in: bounds).isEmpty)
        #expect(TreemapLayout.layout(hotspots: hotspots(5), in: .zero).isEmpty)
        #expect(TreemapLayout.squarify([], in: bounds).isEmpty)
        #expect(TreemapLayout.squarify([0, 0], in: bounds).allSatisfy { $0 == .zero })
    }
}
