//
//  ProjectStore.swift
//  Typstwriter
//

import Foundation
import SwiftUI
import AppKit

/// Persisted list of recently opened project roots, stored as
/// security-scoped bookmarks so the app keeps access across launches.
@Observable
final class ProjectStore {
    static let shared = ProjectStore()

    struct Recent: Identifiable, Hashable {
        let id = UUID()
        let url: URL
    }

    private(set) var recents: [Recent] = []
    private let defaultsKey = "recentProjectBookmarks"
    private let maxRecents = 10

    init() {
        recents = loadBookmarks().compactMap { resolve($0) }.map(Recent.init)
    }

    /// Add a freshly opened URL (already start-accessed by the caller) and
    /// remember it for next launch.
    func remember(_ url: URL) {
        guard let data = makeBookmark(for: url) else { return }
        var bookmarks = loadBookmarks()
        // Move-to-front by resolved path, dedup.
        bookmarks.removeAll { resolve($0)?.standardizedFileURL == url.standardizedFileURL }
        bookmarks.insert(data, at: 0)
        if bookmarks.count > maxRecents { bookmarks.removeLast(bookmarks.count - maxRecents) }
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
        recents = bookmarks.compactMap { resolve($0) }.map(Recent.init)
    }

    func clearRecents() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        recents = []
    }

    /// Resolve the most recent bookmark, starting scoped access on the
    /// returned URL. Caller is responsible for `stopAccessingSecurityScopedResource()`.
    func mostRecentStartingAccess() -> URL? {
        guard let data = loadBookmarks().first, let url = resolve(data) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    // MARK: - Bookmarks

    private func loadBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
