//
//  IndentationComplexity.swift
//  codewake
//
//  Created by Luis Resendez on 18/02/2026.
//

import Foundation

public struct ComplexityScore: Sendable, Hashable {
    /// Sum of every logical line's indentation depth. This is the value hotspot scoring
    /// uses: it grows with both size and nesting, which is what makes a file hard to change.
    public let total: Double
    public let mean: Double
    public let max: Int
    public let logicalLines: Int

    public static let zero = ComplexityScore(total: 0, mean: 0, max: 0, logicalLines: 0)
}

/// Language-agnostic complexity proxy based on indentation depth.
///
/// Deeply indented code is conditional, nested code, and indentation is something every
/// language in a repository already agrees on — so this gives a usable signal on a mixed
/// codebase without a parser per language. It is a proxy, deliberately: it cannot tell a
/// deeply nested loop from a deeply nested data literal.
public enum IndentationComplexity {
    /// Prefixes that usually start a comment. Undercounting a few odd languages is fine;
    /// the score is comparative, not absolute.
    private static let commentPrefixes = ["//", "#", "/*", "*", "--", "<!--", ";;"]

    public static func analyze(_ source: String) -> ComplexityScore {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let width = detectIndentWidth(lines)

        var total = 0
        var maximum = 0
        var count = 0

        for line in lines {
            guard let depth = logicalDepth(of: line, indentWidth: width) else { continue }
            total += depth
            maximum = Swift.max(maximum, depth)
            count += 1
        }

        guard count > 0 else { return .zero }
        return ComplexityScore(
            total: Double(total),
            mean: Double(total) / Double(count),
            max: maximum,
            logicalLines: count
        )
    }

    /// Indentation depth in levels, or nil for blank and comment lines.
    private static func logicalDepth(of line: Substring, indentWidth: Int) -> Int? {
        var columns = 0
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += indentWidth
            } else {
                break
            }
            index = line.index(after: index)
        }

        let body = line[index...]
        guard !body.isEmpty else { return nil }
        if commentPrefixes.contains(where: { body.hasPrefix($0) }) { return nil }
        // A lone closing brace is structural noise that would otherwise inflate the score.
        if body.count == 1, "})]".contains(body.first!) { return nil }

        return columns / indentWidth
    }

    /// Infers the file's indent unit from the smallest indentation it actually uses, so a
    /// 2-space file is not scored as half as complex as an identical 4-space one.
    private static func detectIndentWidth(_ lines: [Substring]) -> Int {
        var smallest = Int.max
        for line in lines {
            var spaces = 0
            for character in line {
                if character == " " { spaces += 1 }
                else if character == "\t" { return 4 }  // tab-indented: one tab is one level
                else { break }
            }
            if spaces > 0 { smallest = min(smallest, spaces) }
        }
        return smallest == Int.max ? 4 : min(max(smallest, 2), 8)
    }
}
