//
//  FileFilterTests.swift
//  codewake
//
//  Created by Luis Resendez on 18/02/2026.
//

import Foundation
import Testing

@testable import CodewakeKit

@Suite("File filter")
struct FileFilterTests {
    @Test(
        "Keeps source files",
        arguments: [
            "src/app.swift",
            "Sources/CodewakeKit/Analysis/HotspotAnalyzer.swift",
            "README.md",
            "lib/vendors.ts",             // "vendors" is not the "vendor" directory
            "app/build_config.py",        // "build_config" is not the "build" directory
        ]
    )
    func keepsSource(path: String) {
        #expect(FileFilter.default.includes(path))
    }

    @Test(
        "Drops generated and vendored files",
        arguments: [
            "package-lock.json",
            "web/pnpm-lock.yaml",
            "node_modules/react/index.js",
            "Pods/Alamofire/Source/Alamofire.swift",
            "dist/bundle.min.js",
            "api/service.pb.go",
            "App.xcodeproj/project.pbxproj",
            ".build/debug/thing.swift",
        ]
    )
    func dropsNoise(path: String) {
        #expect(!FileFilter.default.includes(path))
    }

    @Test("The permissive filter keeps everything")
    func none() {
        #expect(FileFilter.none.includes("package-lock.json"))
        #expect(FileFilter.none.includes("node_modules/react/index.js"))
    }

    /// A lock file out-churns and out-sizes real code by so much that it takes the top
    /// hotspot slot in almost any repository, which is the one place it must never be.
    @Test("Filtered files are absent from history entirely")
    func excludedFromHistory() {
        let commits = [
            HistoryFixture.commit("c0", [
                HistoryFixture.added("src/app.swift", 40),
                HistoryFixture.added("package-lock.json", 9000),
            ]),
            HistoryFixture.commit("c1", [
                HistoryFixture.modified("package-lock.json", added: 4000, removed: 4000),
            ]),
        ]

        let history = RepositoryHistory(name: "fixture", commits: commits)
        #expect(history.files.count == 1)
        #expect(history.files[0].latestPath == "src/app.swift")

        var engine = SnapshotEngine(history: history)
        engine.move(to: 1)
        #expect(engine.currentSnapshot().files.map(\.path) == ["src/app.swift"])

        let unfiltered = RepositoryHistory(name: "fixture", commits: commits, filter: .none)
        #expect(unfiltered.files.count == 2)
    }
}
