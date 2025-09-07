import Foundation
import Observation

@MainActor
@Observable
final class TimelineViewModel {

    enum Filter: String, CaseIterable {
        case all = "All"
        case bluesky = "Bluesky"
        case mastodon = "Mastodon"
    }

    // UI state (plain vars; @Observable tracks mutations)
    private(set) var posts: [UnifiedPost] = []
    var filter: Filter = .all { didSet { applyFilter() } }

    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var error: String? = nil

    // Dependencies
    private let session: SessionStore

    // Per-service caches + cursors
    private var mastodonPosts: [UnifiedPost] = []
    private var blueskyPosts: [UnifiedPost] = []
    private var mastodonCursor: String? = nil
    private var blueskyCursor: String? = nil

    init(session: SessionStore) {
        self.session = session
    }

    // MARK: - Public API used by the view

    func refresh() async {
        // prevent overlapping refreshes (can cause duplicates)
        if isLoading { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let m: Void = fetchMastodon(resetCursor: true)
            async let b: Void = fetchBluesky(resetCursor: true)
            _ = try await (m, b)
            applyFilter()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func onItemAppear(index: Int) {
        let threshold = 5
        guard index >= posts.count - threshold else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        error = nil
        defer { isLoadingMore = false }
        do {
            async let m: Void = fetchMastodon(resetCursor: false)
            async let b: Void = fetchBluesky(resetCursor: false)
            _ = try await (m, b)
            applyFilter()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Internal fetches

    private func fetchMastodon(resetCursor: Bool) async throws {
        guard let client = session.mastodonClient else { return }
        if resetCursor { mastodonCursor = nil; mastodonPosts.removeAll() }
        let (newPosts, next) = try await client.fetchHomeTimeline(cursor: mastodonCursor)
        mastodonCursor = next
        mastodonPosts.append(contentsOf: newPosts)
    }

    private func fetchBluesky(resetCursor: Bool) async throws {
        guard let client = session.blueskyClient else { return }
        if resetCursor { blueskyCursor = nil; blueskyPosts.removeAll() }
        let (newPosts, next) = try await client.fetchHomeTimeline(cursor: blueskyCursor)
        blueskyCursor = next
        blueskyPosts.append(contentsOf: newPosts)
    }

    private func applyFilter() {
        let merged: [UnifiedPost]
        switch filter {
        case .all:
            merged = mastodonPosts + blueskyPosts
        case .bluesky:
            merged = blueskyPosts
        case .mastodon:
            merged = mastodonPosts
        }
        var seen = Set<String>()
        let unique = merged.filter { seen.insert($0.id).inserted }
        posts = unique.sorted { $0.createdAt > $1.createdAt }
    }
}
