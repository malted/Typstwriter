//
//  TypstwriterApp.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/12/26.
//

import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted with `userInfo["url": URL]` to ask the app to open a project root.
    static let openProject = Notification.Name("openProject")
}

@main
struct TypstwriterApp: App {
    @State private var store = ProjectStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    if let url = store.mostRecentStartingAccess() {
                        NotificationCenter.default.post(
                            name: .openProject, object: nil, userInfo: ["url": url]
                        )
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    if store.recents.isEmpty {
                        Text("No Recent Projects").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.recents) { recent in
                            Button(recent.url.lastPathComponent) {
                                openProject(recent.url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") { store.clearRecents() }
                    }
                }
            }
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            openProject(url)
        }
    }

    private func openProject(_ url: URL) {
        store.remember(url)
        NotificationCenter.default.post(
            name: .openProject, object: nil, userInfo: ["url": url]
        )
    }
}
