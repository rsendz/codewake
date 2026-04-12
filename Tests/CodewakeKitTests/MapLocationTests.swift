//
//  MapLocationTests.swift
//  codewake
//
//  Created by Luis Resendez on 12/04/2026.
//

import Foundation
import Testing

@testable import CodewakeKit

@Suite("Map location")
struct MapLocationTests {
    /// Shaped like a repository that has caused trouble: a directory holding only one
    /// subdirectory, two unrelated top-level directories, and a file loose at the root.
    private let paths = [
        ".github/workflows/ci.yml",
        "functions/main.py",
        "functions/util.py",
        "web/src/app/page.tsx",
        "web/src/app/layout.tsx",
        "README.md",
    ]

    @Test("The root shows every file and has no prefix")
    func root() {
        let location = MapLocation()
        #expect(location.isRoot)
        #expect(location.prefix.isEmpty)
        #expect(paths.allSatisfy(location.contains))
        #expect(location.subdirectories(among: paths) == [".github", "functions", "web"])
    }

    @Test("Opening a directory narrows the map to it")
    func opening() {
        var location = MapLocation()
        let opened = location.open("functions", among: paths)
        #expect(opened)
        #expect(location.components == ["functions"])
        #expect(location.prefix == "functions/")
        #expect(location.contains("functions/main.py"))
        #expect(!location.contains("README.md"))
    }

    /// The click that would otherwise land on a level nobody wanted to see.
    @Test("Directories with a single child are descended through")
    func autoDescend() {
        var location = MapLocation()
        location.open(".github", among: paths)
        // .github holds only workflows, which holds only files, so it stops there.
        #expect(location.components == [".github", "workflows"])

        var deeper = MapLocation()
        deeper.open("web", among: paths)
        #expect(deeper.components == ["web", "src", "app"])
    }

    @Test("A directory that is not at this level cannot be opened")
    func illegalMoveIsRefused() {
        var location = MapLocation()
        location.open(".github", among: paths)
        let before = location

        let wrongLevel = location.open("functions", among: paths)
        #expect(!wrongLevel)
        #expect(location == before, "a refused move must change nothing")

        let missing = location.open("nonsense", among: paths)
        #expect(!missing)
        #expect(location == before)
    }

    /// The exact sequence that produced `.github/functions/.github/.github`: the panel lists
    /// the repository's top-level directories, and clicking one has to mean that rather than
    /// "a directory of this name inside wherever I already am".
    @Test("Opening from the root jumps rather than appending")
    func openingFromRoot() {
        var location = MapLocation()
        location.openFromRoot(".github", among: paths)
        #expect(location.components == [".github", "workflows"])

        location.openFromRoot("functions", among: paths)
        #expect(location.components == ["functions"])

        location.openFromRoot(".github", among: paths)
        location.openFromRoot(".github", among: paths)
        #expect(location.components == [".github", "workflows"])
    }

    @Test("A jump to a directory that does not exist leaves the map where it was")
    func failedJumpIsNotAReset() {
        var location = MapLocation()
        location.open("functions", among: paths)
        let jumped = location.openFromRoot("nonsense", among: paths)
        #expect(!jumped)
        #expect(location.components == ["functions"], "a refused jump must not drop to the root")
    }

    @Test("Closing steps back out")
    func closing() {
        var location = MapLocation()
        location.open("web", among: paths)
        #expect(location.components == ["web", "src", "app"])

        location.closeOne()
        #expect(location.components == ["web", "src"])

        location.close(to: 1)
        #expect(location.components == ["web"])

        location.close(to: 0)
        #expect(location.isRoot)
        location.closeOne()
        #expect(location.isRoot, "closing past the root is not an error")
    }

    /// A file sitting directly in a directory means that directory is a place worth being,
    /// even if it also holds exactly one subdirectory.
    @Test("A loose file stops the descent")
    func looseFileStopsDescent() {
        var location = MapLocation()
        let withLooseFile = paths + ["web/package.json"]
        location.open("web", among: withLooseFile)
        #expect(location.components == ["web"])
    }

    @Test("Files at the repository root are not a directory")
    func rootFilesAreNotDirectories() {
        let location = MapLocation()
        #expect(!location.subdirectories(among: paths).contains("README.md"))
        #expect(!location.subdirectories(among: ["README.md"]).contains("/"))
    }
}
