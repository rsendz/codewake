//
//  CodewakeApp.swift
//  codewake
//
//  Created by Luis Resendez on 25/02/2026.
//

import AppKit
import SwiftUI

/// A SwiftPM executable has no app bundle, so it would otherwise launch as a background
/// process with no Dock icon and no way to come to the front.
///
/// This has to happen from the delegate rather than `App.init`: reaching for
/// `NSApplication.shared` before SwiftUI has finished installing its own application
/// object preempts that setup, and the scene's window is then never created at all.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CodewakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView(state: state)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Repository…") {
                    chooseRepository { state.open($0) }
                }
                .keyboardShortcut("o")

                Menu("Open Recent") {
                    ForEach(state.recentRepositories, id: \.self) { url in
                        Button(url.lastPathComponent) { state.open(url) }
                    }
                }
                .disabled(state.recentRepositories.isEmpty)
            }

            CommandGroup(after: .pasteboard) {
                Button("Find File…") { state.focusSearch() }
                    .keyboardShortcut("f")
                    .disabled(!state.isReady)
            }

            CommandMenu("History") {
                Group {
                Button(state.isPlaying ? "Pause" : "Play") { state.togglePlayback() }
                    .keyboardShortcut("p")
                Divider()
                Button("Step Back") { state.step(by: -1) }
                Button("Step Forward") { state.step(by: 1) }
                Button("Jump to First Commit") { state.jumpToStart() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Jump to Latest Commit") { state.jumpToEnd() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Divider()
                Picker("Speed", selection: $state.playbackSpeed) {
                    ForEach(AppState.playbackSpeeds, id: \.self) { speed in
                        Text(speed == speed.rounded() ? "\(Int(speed))x" : "\(speed.formatted())x")
                            .tag(speed)
                    }
                }
                Divider()
                Button("Show Map") { state.viewMode = .map }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Show Ownership") { state.viewMode = .ownership }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Show Age") { state.viewMode = .age }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Close Repository") { state.closeRepository() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                }
                .disabled(!state.isReady)
            }

            CommandGroup(replacing: .help) {
                Button("How to Read Codewake") { state.isShowingHelp = true }
                    .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}
