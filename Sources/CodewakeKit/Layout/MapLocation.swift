//
//  MapLocation.swift
//  codewake
//
//  Created by Luis Resendez on 12/04/2026.
//

import Foundation

/// Where the map is opened to, and which moves from there are legal.
///
/// Opening a directory looks like appending a name to a list, and that is exactly the
/// mistake: the caller holding the name may be looking at a different level than the map
/// is. A panel listing the repository's top-level directories, clicked while the map is
/// already inside one of them, produced paths like `.github/functions/.github` that were
/// never in the repository and could not be closed back out of.
///
/// So a move is checked against the paths that actually exist rather than trusted, and the
/// two kinds of move are named differently instead of sharing one function that cannot tell
/// which was meant.
public struct MapLocation: Sendable, Equatable {
    public private(set) var components: [String]

    public init(components: [String] = []) {
        self.components = components
    }

    public var isRoot: Bool { components.isEmpty }
    public var depth: Int { components.count }

    /// Path prefix every file here shares, with its trailing slash. Empty at the root.
    public var prefix: String {
        components.isEmpty ? "" : components.joined(separator: "/") + "/"
    }

    public func contains(_ path: String) -> Bool {
        components.isEmpty || path.hasPrefix(prefix)
    }

    /// Names of the directories one level below here.
    public func subdirectories(among paths: some Sequence<String>) -> Set<String> {
        var names: Set<String> = []
        for path in paths where contains(path) {
            if let name = component(at: depth, of: path) { names.insert(name) }
        }
        return names
    }

    /// Opens a directory that is a level below this one. Does nothing, and reports false,
    /// when no such directory is there.
    @discardableResult
    public mutating func open(_ name: String, among paths: [String]) -> Bool {
        guard subdirectories(among: paths).contains(name) else { return false }
        descend(into: name, among: paths)
        return true
    }

    /// Opens a top-level directory of the repository, from wherever this is. What a row in
    /// a panel listing the whole repository means, as opposed to a header on the map.
    @discardableResult
    public mutating func openFromRoot(_ name: String, among paths: [String]) -> Bool {
        let previous = components
        components = []
        guard open(name, among: paths) else {
            components = previous
            return false
        }
        return true
    }

    public mutating func close(to depth: Int) {
        components = Array(components.prefix(max(depth, 0)))
    }

    public mutating func closeOne() {
        if !components.isEmpty { components.removeLast() }
    }

    private mutating func descend(into name: String, among paths: [String]) {
        components.append(name)
        // A directory holding one subdirectory and nothing else is not a level worth
        // stopping at. Opening `web` to find only `src` wastes the click and the
        // canvas, so keep going until there is actually a choice to make.
        while let only = onlySubdirectory(among: paths) {
            components.append(only)
        }
    }

    /// The single subdirectory here, when that is the only thing here.
    private func onlySubdirectory(among paths: [String]) -> String? {
        var only: String?
        for path in paths where contains(path) {
            // A file sitting loose at this level means the level has content of its own.
            guard let name = component(at: depth, of: path) else { return nil }
            if only == nil {
                only = name
            } else if only != name {
                return nil
            }
        }
        return only
    }

    /// The path component at `index`, or nil when the path has no directory that deep and
    /// the file is sitting loose at this level.
    private func component(at index: Int, of path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count > index + 1 else { return nil }
        return String(components[index])
    }
}
