//
//  GitRunner.swift
//  codewake
//
//  Created by Luis Resendez on 16/02/2026.
//

import Foundation

public enum GitError: Error, LocalizedError {
    case gitUnavailable
    case notARepository(URL)
    case commandFailed(arguments: [String], status: Int32, message: String)
    case emptyHistory

    public var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "Could not run git. Install the Xcode Command Line Tools with `xcode-select --install`."
        case .notARepository(let url):
            return "\(url.lastPathComponent) is not a Git repository."
        case .commandFailed(let arguments, let status, let message):
            let command = arguments.joined(separator: " ")
            return "git \(command) failed (exit \(status)): \(message)"
        case .emptyHistory:
            return "This repository has no commits yet."
        }
    }
}

/// Runs the system `git` binary inside a repository.
///
/// Every call is one-shot: arguments in, stdout out. stdin, stdout, and stderr are drained
/// concurrently so a large diff can never deadlock against a full pipe buffer.
public struct GitRunner: Sendable {
    public let repositoryURL: URL
    private static let executable = URL(filePath: "/usr/bin/git")
    private static let queue = DispatchQueue(
        label: "com.codewaker.git",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
    }

    @discardableResult
    public func run(_ arguments: [String], stdin: Data? = nil) async throws -> Data {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    do {
                        continuation.resume(returning: try execute(arguments, stdin: stdin, box: box))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    public func runText(_ arguments: [String]) async throws -> String {
        let data = try await run(arguments)
        return String(decoding: data, as: UTF8.self)
    }

    private func execute(_ arguments: [String], stdin: Data?, box: ProcessBox) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: Self.executable.path) else {
            throw GitError.gitUnavailable
        }

        let process = Process()
        process.executableURL = Self.executable
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL

        let output = Pipe()
        let errors = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input

        do {
            try process.run()
        } catch {
            throw GitError.gitUnavailable
        }
        box.adopt(process)

        // stderr and stdin run alongside the stdout read; draining only one of them
        // would stall as soon as another buffer fills.
        let group = DispatchGroup()
        let sideChannels = Mutex(Data())

        Self.queue.async(group: group) {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            sideChannels.withLock { $0 = data }
        }
        Self.queue.async(group: group) {
            if let stdin { try? input.fileHandleForWriting.write(contentsOf: stdin) }
            try? input.fileHandleForWriting.close()
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        group.wait()

        guard process.terminationStatus == 0 else {
            let message = sideChannels.withLock {
                String(decoding: $0, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            throw GitError.commandFailed(
                arguments: arguments,
                status: process.terminationStatus,
                message: message
            )
        }
        return data
    }
}

/// Holds the in-flight process so task cancellation can reach it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func adopt(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            process.terminate()
        } else {
            self.process = process
        }
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }
}

private final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
