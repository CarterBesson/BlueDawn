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
        if isLoading { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        func fetchMastodonWrapper() async -> Result<Void, Error> {
            do {
                try await fetchMastodon(resetCursor: true)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        func fetchBlueskyWrapper() async -> Result<Void, Error> {
            do {
                try await fetchBluesky(resetCursor: true)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        let mResult = await fetchMastodonWrapper()
        var bResult = await fetchBlueskyWrapper()

        if case .failure(let bError) = bResult,
           case BlueskyClient.APIError.badStatus(let code, _) = bError, code == 401 {
            if await session.refreshBlueskyIfNeeded() {
                do {
                    try await fetchBluesky(resetCursor: true)
                    bResult = .success(())
                } catch {
                    bResult = .failure(error)
                }
            } else {
                session.signOutBluesky()
            }
        }

        applyFilter()

        if case .failure = mResult, case .failure(let bError) = bResult {
            self.error = (bError as? LocalizedError)?.errorDescription ?? bError.localizedDescription
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

        func fetchMastodonWrapper() async -> Result<Void, Error> {
            do {
                try await fetchMastodon(resetCursor: false)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        func fetchBlueskyWrapper() async -> Result<Void, Error> {
            do {
                try await fetchBluesky(resetCursor: false)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        let mResult = await fetchMastodonWrapper()
        var bResult = await fetchBlueskyWrapper()

        if case .failure(let bError) = bResult,
           case BlueskyClient.APIError.badStatus(let code, _) = bError, code == 401 {
            if await session.refreshBlueskyIfNeeded() {
                do {
                    try await fetchBluesky(resetCursor: false)
                    bResult = .success(())
                } catch {
                    bResult = .failure(error)
                }
            } else {
                session.signOutBluesky()
            }
        }

        applyFilter()

        if case .failure = mResult, case .failure(let bError) = bResult {
            self.error = (bError as? LocalizedError)?.errorDescription ?? bError.localizedDescription
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
