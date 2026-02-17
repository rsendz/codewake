//
//  GitLogParserTests.swift
//  codewake
//
//  Created by Luis Resendez on 17/02/2026.
//

import Foundation
import Testing

@testable import CodewakerKit

/// Real output captured from `git log --raw --numstat --no-abbrev -M` on a scratch
/// repository covering an add, a rename with edits, a binary file, and a delete.
private let sampleLog = """
\u{1e}e13e4f99f65c2888249ffed84f8b01f37cdd1d71\u{1f}Tester\u{1f}t@t.com\u{1f}1788811425\u{1f}first commit

:000000 100644 0000000000000000000000000000000000000000 587be6b4c3f93f93c489c0111bba5596147a26cb A\tsrc/deep/two.swift
:000000 100644 0000000000000000000000000000000000000000 de980441c3ab03a8c07dda1ad27b8a11f39deb1e A\tsrc/one.swift
1\t0\tsrc/deep/two.swift
3\t0\tsrc/one.swift
\u{1e}45b870f52744cdc3f2976e4540186c494f769bcb\u{1f}Tester\u{1f}t@t.com\u{1f}1788811426\u{1f}rename and grow

:000000 100644 0000000000000000000000000000000000000000 0f49c4ae77b43dff338093c78e009676e7e308ba A\tblob.bin
:100644 100644 de980441c3ab03a8c07dda1ad27b8a11f39deb1e 940532533944dd159bfd11136fac2ee35872de38 R060\tsrc/one.swift\tsrc/deep/renamed.swift
-\t-\tblob.bin
2\t0\tsrc/{one.swift => deep/renamed.swift}
\u{1e}84c1340c33ae9e978c46b3b9b3aae3f8f345196d\u{1f}Tester\u{1f}t@t.com\u{1f}1788811427\u{1f}delete two

:100644 000000 587be6b4c3f93f93c489c0111bba5596147a26cb 0000000000000000000000000000000000000000 D\tsrc/deep/two.swift
0\t1\tsrc/deep/two.swift
"""

@Suite("Git log parsing")
struct GitLogParserTests {
    @Test("Reads commit metadata")
    func metadata() throws {
        let commits = GitLogParser.parse(sampleLog)
        #expect(commits.count == 3)

        let first = try #require(commits.first)
        #expect(first.sha == "e13e4f99f65c2888249ffed84f8b01f37cdd1d71")
        #expect(first.authorName == "Tester")
        #expect(first.authorEmail == "t@t.com")
        #expect(first.subject == "first commit")
        #expect(first.date == Date(timeIntervalSince1970: 1788811425))
    }

    @Test("Joins line counts onto the right file")
    func lineCounts() throws {
        let commits = GitLogParser.parse(sampleLog)
        let added = try #require(commits[0].changes.first { $0.path == "src/one.swift" })
        #expect(added.kind == .added)
        #expect(added.insertions == 3)
        #expect(added.deletions == 0)
        #expect(added.blobSHA == "de980441c3ab03a8c07dda1ad27b8a11f39deb1e")
    }

    @Test("Resolves a rename to both of its paths")
    func rename() throws {
        let commits = GitLogParser.parse(sampleLog)
        let renamed = try #require(commits[1].changes.first { $0.path == "src/deep/renamed.swift" })
        #expect(renamed.kind == .renamed(from: "src/one.swift"))
        #expect(renamed.previousPath == "src/one.swift")
        // Line counts come from the brace-compressed numstat path, which has to be
        // expanded before it will match the raw line's destination.
        #expect(renamed.insertions == 2)
        #expect(renamed.blobSHA == "940532533944dd159bfd11136fac2ee35872de38")
    }

    @Test("Marks binary files and scores them no churn")
    func binary() throws {
        let commits = GitLogParser.parse(sampleLog)
        let binary = try #require(commits[1].changes.first { $0.path == "blob.bin" })
        #expect(binary.isBinary)
        #expect(binary.kind == .added)
        #expect(binary.churn == 0)
    }

    @Test("Deletions carry no post-image blob")
    func deletion() throws {
        let commits = GitLogParser.parse(sampleLog)
        let deleted = try #require(commits[2].changes.first)
        #expect(deleted.kind == .deleted)
        #expect(deleted.path == "src/deep/two.swift")
        #expect(deleted.deletions == 1)
        #expect(deleted.blobSHA == nil)
    }

    @Test(
        "Expands numstat rename paths",
        arguments: [
            ("src/{one.swift => deep/renamed.swift}", "src/deep/renamed.swift"),
            ("old.swift => new.swift", "new.swift"),
            ("{old => new}/file.swift", "new/file.swift"),
            ("src/{ => nested}/file.swift", "src/nested/file.swift"),
            ("plain/path.swift", "plain/path.swift"),
        ]
    )
    func renamePathExpansion(input: String, expected: String) {
        #expect(GitLogParser.expandRenamePath(input) == expected)
    }

    @Test("Survives a subject containing the field separator")
    func awkwardSubject() throws {
        let log = "\u{1e}abc\u{1f}A\u{1f}a@b.c\u{1f}100\u{1f}fix: a\u{1f}b\n"
        let commit = try #require(GitLogParser.parse(log).first)
        #expect(commit.subject == "fix: a\u{1f}b")
    }

    @Test("Ignores an empty commit's missing diff section")
    func emptyCommit() throws {
        let log = "\u{1e}abc\u{1f}A\u{1f}a@b.c\u{1f}100\u{1f}empty\n\n"
        let commit = try #require(GitLogParser.parse(log).first)
        #expect(commit.changes.isEmpty)
        #expect(commit.totalChurn == 0)
    }
}

@Suite("cat-file batch parsing")
struct BatchParsingTests {
    @Test("Splits objects by declared byte length")
    func batch() {
        var data = Data()
        data.append(contentsOf: Data("aaa blob 5\nhello\n".utf8))
        data.append(contentsOf: Data("bbb missing\n".utf8))
        data.append(contentsOf: Data("ccc blob 3\nbye\n".utf8))

        let blobs = GitCLIHistoryProvider.parseBatch(data)
        #expect(blobs == ["aaa": "hello", "ccc": "bye"])
    }

    @Test("Skips binary payloads without disturbing the ones after them")
    func binaryPayload() {
        var data = Data("aaa blob 3\n".utf8)
        data.append(contentsOf: [0x01, 0x00, 0x02])  // contains NUL, so: binary
        data.append(contentsOf: Data("\nbbb blob 4\ntext\n".utf8))

        let blobs = GitCLIHistoryProvider.parseBatch(data)
        #expect(blobs["aaa"] == nil)
        #expect(blobs["bbb"] == "text")
    }
}
