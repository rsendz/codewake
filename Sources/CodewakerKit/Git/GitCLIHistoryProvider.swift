//
//  GitCLIHistoryProvider.swift
//  codewake
//
//  Created by Luis Resendez on 17/02/2026.
//

import Foundation

/// Reads history by shelling out to the system `git`.
public struct GitCLIHistoryProvider: HistoryProvider {
    public let repositoryURL: URL
    private let runner: GitRunner

    /// Blobs larger than this are skipped rather than decoded — complexity numbers for
    /// generated or vendored megafiles are noise, and holding them costs real memory.
    private static let maximumBlobBytes = 2 * 1024 * 1024

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
        self.runner = GitRunner(repositoryURL: repositoryURL)
    }

    public var name: String { repositoryURL.lastPathComponent }

    static let logArguments = [
        "-c", "core.quotePath=false",
        // git silently stops looking for renames in commits touching more files than this.
        // Large refactors are exactly where losing file identity hurts most, so it is worth
        // paying for a higher ceiling than the default 1000.
        "-c", "diff.renameLimit=5000",
        "log",
        "--reverse",
        "--no-merges",     // merge numstat double-counts churn already attributed to the branch
        "--raw",
        "--numstat",
        "--no-abbrev",     // full blob SHAs, so they can be used as cache keys
        // Detect renames, so a file keeps its identity across moves. The threshold is
        // deliberately below git's default 50%: a file moved and reworked in one commit
        // still tells one continuous story, and losing that story costs more here than an
        // occasional wrong link between two small files.
        "-M40%",
        "--no-color",
        "--format=%x1e%H%x1f%an%x1f%ae%x1f%at%x1f%s",
    ]

    public func loadCommits() async throws -> [Commit] {
        try await validateRepository()
        let output = try await runner.runText(Self.logArguments)
        let commits = GitLogParser.parse(output)
        guard !commits.isEmpty else { throw GitError.emptyHistory }
        return commits
    }

    private func validateRepository() async throws {
        do {
            _ = try await runner.run(["rev-parse", "--git-dir"])
        } catch let error as GitError {
            if case .commandFailed = error { throw GitError.notARepository(repositoryURL) }
            throw error
        }
    }

    public func loadBlobs(shas: [String]) async throws -> [String: String] {
        guard !shas.isEmpty else { return [:] }
        let request = Data((shas.joined(separator: "\n") + "\n").utf8)
        let output = try await runner.run(["cat-file", "--batch"], stdin: request)
        return Self.parseBatch(output)
    }

    /// `git cat-file --batch` emits `<sha> <type> <size>\n<contents>\n` per object, or
    /// `<sha> missing\n` for one it cannot find. Sizes are byte counts, so this walks the
    /// buffer by offset rather than splitting on newlines.
    static func parseBatch(_ data: Data) -> [String: String] {
        var blobs: [String: String] = [:]
        var index = data.startIndex

        while index < data.endIndex {
            guard let newline = data[index...].firstIndex(of: UInt8(ascii: "\n")) else { break }
            let header = String(decoding: data[index..<newline], as: UTF8.self)
            index = data.index(after: newline)

            let fields = header.split(separator: " ")
            guard fields.count >= 3, let size = Int(fields[2]) else {
                continue  // "missing" or "ambiguous": no payload follows, move to the next header
            }

            let contentEnd = data.index(index, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            let body = data[index..<contentEnd]
            if size <= maximumBlobBytes, !body.contains(0) {
                blobs[String(fields[0])] = String(decoding: body, as: UTF8.self)
            }
            // Skip the payload plus the trailing newline git appends after each object.
            index = data.index(contentEnd, offsetBy: 1, limitedBy: data.endIndex) ?? data.endIndex
        }
        return blobs
    }
}
