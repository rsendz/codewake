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
public enum GitLogParser {
    static let recordSeparator: Character = "\u{1e}"
    static let fieldSeparator: Character = "\u{1f}"

    public static func parse(_ output: String) -> [Commit] {
        output
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { parseRecord($0) }
    }

    private static func parseRecord(_ record: Substring) -> Commit? {
        var lines = record.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return nil }
        let header = lines.removeFirst()

        // maxSplits keeps a subject containing the field separator intact.
        let fields = header.split(
            separator: fieldSeparator,
            maxSplits: 4,
            omittingEmptySubsequences: false
        )
        guard fields.count == 5, let timestamp = TimeInterval(fields[3]) else { return nil }

        var counts: [String: LineCounts] = [:]
        var raws: [RawEntry] = []
        for line in lines where !line.isEmpty {
            if line.hasPrefix(":") {
                if let raw = parseRawLine(line) { raws.append(raw) }
            } else if let stat = parseNumstatLine(line) {
                counts[stat.path] = stat.counts
            }
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
            sha: String(fields[0]),
            authorName: String(fields[1]),
            authorEmail: String(fields[2]),
            date: Date(timeIntervalSince1970: timestamp),
            subject: String(fields[4]),
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
    private static func parseRawLine(_ line: Substring) -> RawEntry? {
        let parts = line.dropFirst().split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        let meta = parts[0].split(separator: " ", omittingEmptySubsequences: true)
        guard meta.count >= 5 else { return nil }
        let newSHA = String(meta[3])
        let status = meta[4]
        guard let statusLetter = status.first else { return nil }

        let source = unquotePath(parts[1])
        let destination = parts.count >= 3 ? unquotePath(parts[2]) : source

        let kind: FileChange.Kind
        switch statusLetter {
        case "A": kind = .added
        case "D": kind = .deleted
        case "R": kind = .renamed(from: source)
        // A copy creates a file that did not exist before, so it behaves like an add.
        case "C": kind = .added
        // M, T (type change), and the unmerged/unknown letters all mean "content changed".
        default: kind = .modified
        }

        let isNullSHA = newSHA.allSatisfy { $0 == "0" }
        return RawEntry(path: destination, kind: kind, blobSHA: isNullSHA ? nil : newSHA)
    }

    // MARK: - Numstat lines

    private struct LineCounts {
        let insertions: Int
        let deletions: Int
        let isBinary: Bool
    }

    /// `<insertions>\t<deletions>\t<path>`, where a binary file reports `-` for both counts
    /// and a rename may compress its two paths into `dir/{old => new}.swift`.
    private static func parseNumstatLine(_ line: Substring) -> (path: String, counts: LineCounts)? {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        let isBinary = parts[0] == "-"
        let path = expandRenamePath(unquotePath(parts[2]))
        return (
            path,
            LineCounts(
                insertions: Int(parts[0]) ?? 0,
                deletions: Int(parts[1]) ?? 0,
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

    /// git quotes paths containing control characters or non-UTF-8 bytes even with
    /// `core.quotePath=false`. Those are rare enough to just strip the quoting from.
    private static func unquotePath(_ path: Substring) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 else {
            return String(path)
        }
        return path.dropFirst().dropLast()
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
