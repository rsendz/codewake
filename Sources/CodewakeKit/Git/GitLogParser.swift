//
//  GitLogParser.swift
//  codewake
//
//  Created by Luis Resendez on 17/02/2026.
//

import Foundation

/// Parses the output of `GitCLIHistoryProvider.logArguments`.
///
/// Each commit record looks like:
/// ```
/// \x1eSHA\x1fname\x1femail\x1funix-time\x1fsubject
///
/// :100644 100644 <oldsha> <newsha> R060\tsrc/one.swift\tsrc/deep/renamed.swift
/// 2\t0\tsrc/{one.swift => deep/renamed.swift}
/// ```
/// The `--raw` lines are authoritative for identity (status letter, blob SHA, and both
/// sides of a rename); the `--numstat` lines only supply line counts and are joined onto
/// the raw lines by destination path, since the two sections are not ordered alike.
///
/// The work happens over raw UTF-8 bytes rather than `String`. Every separator here is a
/// single ASCII byte, so splitting on `Character` buys nothing and pays for grapheme
/// breaking over the whole log. On git's own history — 28 MB, 60,896 commits — the
/// `String` version took 1.54s and this one takes 0.21s, for identical output. Strings are
/// built only for the fields that are kept.
public enum GitLogParser {
    private static let recordSeparator = UInt8(ascii: "\u{1e}")
    private static let fieldSeparator = UInt8(ascii: "\u{1f}")
    private static let newline = UInt8(ascii: "\n")
    private static let tab = UInt8(ascii: "\t")
    private static let space = UInt8(ascii: " ")

    public static func parse(_ output: String) -> [Commit] {
        var bytes = Array(output.utf8)
        return bytes.withUnsafeMutableBufferPointer { parse(UnsafeBufferPointer($0)) }
    }

    /// Parses straight out of git's stdout, without decoding it into a `String` first.
    public static func parse(_ data: Data) -> [Commit] {
        data.withUnsafeBytes { raw in
            parse(raw.bindMemory(to: UInt8.self))
        }
    }

    private static func parse(_ bytes: UnsafeBufferPointer<UInt8>) -> [Commit] {
        var commits: [Commit] = []
        var start = 0
        while start < bytes.count {
            guard let separator = index(of: recordSeparator, in: bytes, from: start) else {
                if let commit = parseRecord(bytes, start..<bytes.count) { commits.append(commit) }
                break
            }
            if separator > start, let commit = parseRecord(bytes, start..<separator) {
                commits.append(commit)
            }
            start = separator + 1
        }
        return commits
    }

    private static func parseRecord(_ bytes: UnsafeBufferPointer<UInt8>, _ record: Range<Int>) -> Commit? {
        guard !record.isEmpty else { return nil }
        let headerEnd = index(of: newline, in: bytes, from: record.lowerBound, limit: record.upperBound)
            ?? record.upperBound

        // maxSplits keeps a subject containing the field separator intact.
        var fields = [Range<Int>]()
        fields.reserveCapacity(5)
        split(bytes, record.lowerBound..<headerEnd, on: fieldSeparator, maxSplits: 4, into: &fields)
        guard fields.count == 5, let timestamp = decimal(bytes, fields[3]) else { return nil }

        var counts: [String: LineCounts] = [:]
        var raws: [RawEntry] = []

        var lineStart = min(headerEnd + 1, record.upperBound)
        while lineStart < record.upperBound {
            let lineEnd = index(of: newline, in: bytes, from: lineStart, limit: record.upperBound)
                ?? record.upperBound
            let line = lineStart..<lineEnd
            if !line.isEmpty {
                if bytes[line.lowerBound] == UInt8(ascii: ":") {
                    if let raw = parseRawLine(bytes, line) { raws.append(raw) }
                } else if let stat = parseNumstatLine(bytes, line) {
                    counts[stat.path] = stat.counts
                }
            }
            lineStart = lineEnd + 1
        }

        let changes = raws.map { raw -> FileChange in
            let counts = counts[raw.path] ?? LineCounts(insertions: 0, deletions: 0, isBinary: false)
            return FileChange(
                path: raw.path,
                insertions: counts.insertions,
                deletions: counts.deletions,
                kind: raw.kind,
                isBinary: counts.isBinary,
                blobSHA: raw.blobSHA
            )
        }

        return Commit(
            sha: string(bytes, fields[0]),
            authorName: string(bytes, fields[1]),
            authorEmail: string(bytes, fields[2]),
            date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            subject: string(bytes, fields[4]),
            changes: changes
        )
    }

    // MARK: - Raw lines

    private struct RawEntry {
        let path: String
        let kind: FileChange.Kind
        let blobSHA: String?
    }

    /// `:<oldmode> <newmode> <oldsha> <newsha> <status>\t<path>[\t<destination>]`
    private static func parseRawLine(_ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> RawEntry? {
        var parts = [Range<Int>]()
        parts.reserveCapacity(3)
        split(bytes, (line.lowerBound + 1)..<line.upperBound, on: tab, maxSplits: 2, into: &parts)
        guard parts.count >= 2 else { return nil }

        var meta = [Range<Int>]()
        meta.reserveCapacity(5)
        split(bytes, parts[0], on: space, maxSplits: 4, into: &meta, omittingEmpty: true)
        guard meta.count >= 5, !meta[4].isEmpty else { return nil }

        let newSHA = meta[3]
        let source = unquotedPath(bytes, parts[1])
        let destination = parts.count >= 3 ? unquotedPath(bytes, parts[2]) : source

        let kind: FileChange.Kind
        switch bytes[meta[4].lowerBound] {
        case UInt8(ascii: "A"): kind = .added
        case UInt8(ascii: "D"): kind = .deleted
        case UInt8(ascii: "R"): kind = .renamed(from: source)
        // A copy creates a file that did not exist before, so it behaves like an add.
        case UInt8(ascii: "C"): kind = .added
        // M, T (type change), and the unmerged/unknown letters all mean "content changed".
        default: kind = .modified
        }

        let isNullSHA = newSHA.allSatisfy { bytes[$0] == UInt8(ascii: "0") }
        return RawEntry(path: destination, kind: kind, blobSHA: isNullSHA ? nil : string(bytes, newSHA))
    }

    // MARK: - Numstat lines

    private struct LineCounts {
        let insertions: Int
        let deletions: Int
        let isBinary: Bool
    }

    /// `<insertions>\t<deletions>\t<path>`, where a binary file reports `-` for both counts
    /// and a rename may compress its two paths into `dir/{old => new}.swift`.
    private static func parseNumstatLine(
        _ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>
    ) -> (path: String, counts: LineCounts)? {
        var parts = [Range<Int>]()
        parts.reserveCapacity(3)
        split(bytes, line, on: tab, maxSplits: 2, into: &parts)
        guard parts.count == 3 else { return nil }

        let isBinary = parts[0].count == 1 && bytes[parts[0].lowerBound] == UInt8(ascii: "-")
        return (
            expandRenamePath(unquotedPath(bytes, parts[2])),
            LineCounts(
                insertions: decimal(bytes, parts[0]) ?? 0,
                deletions: decimal(bytes, parts[1]) ?? 0,
                isBinary: isBinary
            )
        )
    }

    /// Resolves the destination side of a numstat rename path.
    ///
    /// `src/{one.swift => deep/renamed.swift}` -> `src/deep/renamed.swift`
    /// `old.swift => new.swift`                -> `new.swift`
    static func expandRenamePath(_ path: String) -> String {
        guard let arrow = path.range(of: " => ") else { return path }

        guard let open = path.range(of: "{", range: path.startIndex..<arrow.lowerBound),
              let close = path.range(of: "}", range: arrow.upperBound..<path.endIndex)
        else {
            return String(path[arrow.upperBound...])
        }

        let prefix = path[path.startIndex..<open.lowerBound]
        let middle = path[arrow.upperBound..<close.lowerBound]
        let suffix = path[close.upperBound...]
        // An empty brace side collapses a path segment, leaving a doubled slash behind.
        return (prefix + middle + suffix).replacingOccurrences(of: "//", with: "/")
    }

    // MARK: - Byte helpers

    private static func index(
        of byte: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from start: Int, limit: Int? = nil
    ) -> Int? {
        let end = limit ?? bytes.count
        var index = start
        while index < end {
            if bytes[index] == byte { return index }
            index += 1
        }
        return nil
    }

    /// Splits `range` on `separator`, appending at most `maxSplits + 1` sub-ranges.
    private static func split(
        _ bytes: UnsafeBufferPointer<UInt8>,
        _ range: Range<Int>,
        on separator: UInt8,
        maxSplits: Int,
        into parts: inout [Range<Int>],
        omittingEmpty: Bool = false
    ) {
        var start = range.lowerBound
        var splits = 0
        var index = range.lowerBound
        while index < range.upperBound {
            if bytes[index] == separator, splits < maxSplits {
                if !omittingEmpty || index > start {
                    parts.append(start..<index)
                    splits += 1
                }
                start = index + 1
            }
            index += 1
        }
        if !omittingEmpty || start < range.upperBound {
            parts.append(start..<range.upperBound)
        }
    }

    private static func decimal(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Int? {
        guard !range.isEmpty else { return nil }
        var value = 0
        for index in range {
            let digit = bytes[index] &- UInt8(ascii: "0")
            guard digit < 10 else { return nil }
            value = value * 10 + Int(digit)
        }
        return value
    }

    private static func string(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
    }

    /// git quotes paths containing control characters or non-UTF-8 bytes even with
    /// `core.quotePath=false`. Those are rare enough to just strip the quoting from.
    private static func unquotedPath(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> String {
        let quote = UInt8(ascii: "\"")
        guard range.count >= 2, bytes[range.lowerBound] == quote, bytes[range.upperBound - 1] == quote
        else {
            return string(bytes, range)
        }
        return string(bytes, (range.lowerBound + 1)..<(range.upperBound - 1))
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
