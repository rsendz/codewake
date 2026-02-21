//
//  CodewakerApp.swift
//  codewake
//
//  Created by Luis Resendez on 21/02/2026.
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
struct CodewakerApp: App {
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
            }
            CommandGroup(after: .toolbar) {
                Button(state.isPlaying ? "Pause" : "Play History") {
                    state.togglePlayback()
                }
                .keyboardShortcut("p")
                .disabled(!state.isReady)

                Button("Close Repository") {
                    state.closeRepository()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!state.isReady)
            }
        }
    }
}
