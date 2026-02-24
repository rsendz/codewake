//
//  FileFilter.swift
//  codewake
//
//  Created by Luis Resendez on 18/02/2026.
//

import Foundation

/// Decides which files count as part of the codebase.
///
/// Generated and vendored files are the loudest thing in most repositories — a lock file
/// churns enormously and is enormous, so it wins the hotspot ranking outright and buries
/// the code the ranking is supposed to be about. Nobody has ever needed telling that
/// `package-lock.json` changes a lot, so it is excluded before analysis rather than
/// explained away afterwards.
public struct FileFilter: Sendable {
    /// A path is excluded when any of its directory components matches.
    public var excludedDirectories: Set<String>
    /// A path is excluded when its final component matches exactly.
    public var excludedFilenames: Set<String>
    /// A path is excluded when its final component ends with one of these.
    public var excludedSuffixes: [String]

    public init(
        excludedDirectories: Set<String>,
        excludedFilenames: Set<String>,
        excludedSuffixes: [String]
    ) {
        self.excludedDirectories = excludedDirectories
        self.excludedFilenames = excludedFilenames
        self.excludedSuffixes = excludedSuffixes
    }

    public static let `default` = FileFilter(
        excludedDirectories: [
            "node_modules", "vendor", "vendored", "third_party", "thirdparty",
            "Pods", "Carthage", "bower_components",
            ".build", "build", "dist", "out", "target", ".next", ".nuxt",
            "coverage", "__snapshots__", "Generated", "generated",
            ".git", ".yarn", "Godeps",
        ],
        excludedFilenames: [
            "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "npm-shrinkwrap.json",
            "Cargo.lock", "Gemfile.lock", "composer.lock", "poetry.lock", "uv.lock",
            "Podfile.lock", "pubspec.lock", "mix.lock", "go.sum", "flake.lock",
            "Package.resolved",
        ],
        excludedSuffixes: [
            ".min.js", ".min.css", ".map",
            ".pb.go", ".pb.swift", ".pb.cc", ".pb.h", "_pb2.py",
            ".generated.swift", ".g.dart", ".freezed.dart",
            ".pbxproj", ".xcworkspacedata", ".snap",
        ]
    )

    /// Keeps everything. Useful for tests and for anyone who wants the raw picture.
    public static let none = FileFilter(
        excludedDirectories: [], excludedFilenames: [], excludedSuffixes: []
    )

    public func includes(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard let filename = components.last else { return false }

        if components.dropLast().contains(where: { excludedDirectories.contains(String($0)) }) {
            return false
        }
        if excludedFilenames.contains(String(filename)) { return false }
        return !excludedSuffixes.contains { filename.hasSuffix($0) }
    }
}
