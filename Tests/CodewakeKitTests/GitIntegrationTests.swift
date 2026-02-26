//
//  GitIntegrationTests.swift
//  codewake
//
//  Created by Luis Resendez on 17/02/2026.
//

import Foundation
import Testing

@testable import CodewakeKit

/// Drives the real `git` binary against a repository built for the test, so the argument
/// list and the parser are checked against git's actual output rather than a fixture that
/// could drift from it.
@Suite("Git integration", .serialized)
struct GitIntegrationTests {
    private func makeRepository() throws -> URL {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "codewake-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        /// Fails loudly: a fixture command that quietly does nothing shows up later as a
        /// baffling assertion failure somewhere else entirely.
        func git(_ arguments: [String], sourceLocation: SourceLocation = #_sourceLocation) throws {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = url
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            try process.run()
            let message = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            try #require(
                process.terminationStatus == 0,
                "git \(arguments.joined(separator: " ")) failed: \(String(decoding: message, as: UTF8.self))",
                sourceLocation: sourceLocation
            )
        }

        func write(_ contents: String, to path: String) throws {
            let file = url.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }

        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Ada"])
        try git(["config", "user.email", "ada@example.com"])

        try write("func f() {\n    if x {\n        go()\n    }\n}\n", to: "src/app.swift")
        try write("# Docs\n", to: "README.md")
        try git(["add", "-A"])
        try git(["commit", "-qm", "initial commit"])

        try FileManager.default.createDirectory(
            at: url.appending(path: "src/core"), withIntermediateDirectories: true
        )
        try git(["mv", "src/app.swift", "src/core/app.swift"])
        try git(["add", "-A"])
        try git(["-c", "user.name=Grace", "-c", "user.email=grace@example.com",
                 "commit", "-qm", "move into core"])

        try write("func f() {\n    if x {\n        while y {\n            go()\n        }\n    }\n}\n",
                  to: "src/core/app.swift")
        try git(["add", "-A"])
        try git(["commit", "-qm", "add a loop"])

        try git(["rm", "-q", "README.md"])
        try git(["commit", "-qm", "drop docs"])

        return url
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Loads a real repository end to end")
    func endToEnd() async throws {
        let repository = try makeRepository()
        defer { cleanUp(repository) }

        let engine = try await AnalysisEngine.load(
            from: GitCLIHistoryProvider(repositoryURL: repository)
        )

        #expect(engine.summary.commitCount == 4)
        #expect(engine.summary.commits[0].subject == "initial commit")
        #expect(engine.summary.commits[1].authorName == "Grace")

        // The rename must not have created a second file identity.
        #expect(engine.summary.fileCount == 2)

        let hotspots = try await engine.refinedHotspots(at: 3)
        #expect(hotspots.count == 1)  // README.md is deleted by this point
        let app = try #require(hotspots.first)
        #expect(app.path == "src/core/app.swift")
        // Blob contents were read, so this is a measured score rather than a size estimate.
        #expect(!app.isEstimated)
        #expect(app.complexity?.max == 3)

        let statistics = await engine.statistics(at: 0)
        #expect(statistics.fileCount == 2)

        // Timeline order and displayed dates must agree, or scrubbing forward would
        // sometimes show an earlier date than the commit before it.
        let dates = engine.summary.commits.map(\.date)
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("File detail reports every author who touched the file")
    func fileDetail() async throws {
        let repository = try makeRepository()
        defer { cleanUp(repository) }

        let engine = try await AnalysisEngine.load(
            from: GitCLIHistoryProvider(repositoryURL: repository)
        )
        let hotspots = try await engine.refinedHotspots(at: 3)
        let app = try #require(hotspots.first)
        let detail = try #require(await engine.detail(for: app.id, at: 3))

        #expect(detail.wasRenamed)
        #expect(detail.churnHistory.count == 3)  // created, moved, edited
        #expect(Set(detail.authors.map(\.name)) == ["Ada", "Grace"])
        #expect(detail.recentCommits.first?.subject == "add a loop")
    }

    @Test("Scrubbing to an earlier commit restores the file that was later deleted")
    func scrubbingBackInTime() async throws {
        let repository = try makeRepository()
        defer { cleanUp(repository) }

        let engine = try await AnalysisEngine.load(
            from: GitCLIHistoryProvider(repositoryURL: repository)
        )

        _ = await engine.hotspots(at: 3)
        let earlier = await engine.hotspots(at: 0)
        #expect(earlier.contains { $0.path == "README.md" })
        #expect(earlier.contains { $0.path == "src/app.swift" })  // pre-rename path
    }

    @Test("A directory that is not a repository reports that clearly")
    func notARepository() async throws {
        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "codewake-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { cleanUp(directory) }

        await #expect(throws: GitError.self) {
            try await GitCLIHistoryProvider(repositoryURL: directory).loadCommits()
        }
    }
}
