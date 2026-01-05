import SwiftUI

enum TimelineFilter: String, CaseIterable {
    case all = "All"
    case bluesky = "Bluesky"
    case mastodon = "Mastodon"
}

// Thin wrapper screen that owns timeline state and embeds TimelineList
struct HomeTimelineView: View {
    @Environment(SessionStore.self) private var session
    @Binding var filter: TimelineFilter

    // Timeline state
    @State private var posts: [UnifiedPost] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var error: String? = nil

    // Persisted unified store (newest → oldest). Never resort wholesale; insert incrementally.
    @State private var allPosts: [UnifiedPost] = []
    @State private var idSet: Set<String> = []

    // Cached filtered results for performance
    @State private var cachedAllPosts: [UnifiedPost] = []
    @State private var cachedBlueskyPosts: [UnifiedPost] = []
    @State private var cachedMastodonPosts: [UnifiedPost] = []
    @State private var filterCacheValid = false

    // Pagination anchors
    @State private var mastodonBottomCursor: String? = nil // for older pages (max_id)
    @State private var blueskyBottomCursor: String? = nil  // for older pages (cursor)
    @State private var mastodonNewestID: String? = nil     // for newer pages (since_id)
    @State private var currentAnchorID: String? = nil      // last visible item id to preserve position across sessions

    // Retention / compaction settings
    private let retentionMaxCount = 1400
    private let retentionHighWater = 1650
    private let retentionAgeDays: Int = 30
    private let retentionAnchorBuffer = 120

    // Minimal state required by TimelineList
    @State private var anchorID: String? = nil
    @State private var pendingScrollToID: String? = nil
    @State private var jumpInProgress = false
    @State private var suppressAnchorUpdates = false
    @State private var imageViewer: ImageViewerState? = nil
    @State private var postSelection: UnifiedPost? = nil
    @State private var safariURL: URL? = nil
    @State private var showMyProfiles: Bool = false
    @State private var didInitialRestore: Bool = false
    @State private var toastText: String? = nil

    private struct ProfileRoute: Identifiable, Hashable {
        let id = UUID()
        let network: Network
        let handle: String
    }
    @State private var profileRoute: ProfileRoute? = nil

    private var aboveCount: Int {
        guard let anchorID,
              let idx = posts.firstIndex(where: { $0.id == anchorID }) else { return 0 }
        return idx // number of items before the anchor
    }

    var body: some View {
        TimelineList(
            posts: posts,
            isLoadingMore: isLoadingMore,
            session: session,
            onItemAppear: { onItemAppear(index: $0) },
            onOpenPost: { post in
                postSelection = post
            },
            anchorID: $anchorID,
            pendingScrollToID: $pendingScrollToID,
            jumpInProgress: $jumpInProgress,
            suppressAnchorUpdates: $suppressAnchorUpdates,
            didInitialRestore: didInitialRestore,
            onOpenProfile: { network, handle in
                profileRoute = ProfileRoute(network: network, handle: handle)
            },
            onTapImage: { tappedPost, idx in imageViewer = ImageViewerState(post: tappedPost, index: idx) },
            onOpenExternalURL: { url in
                #if canImport(SafariServices) && canImport(UIKit)
                safariURL = url
                #endif
            },
            onRefresh: {
                // Preserve current anchor and explicitly restore it after refresh
                let preserved = anchorID
                jumpInProgress = true
                await refresh()
                if let preserved {
                    // Reassert anchor and request a programmatic scroll to neutralize any jump
                    anchorID = preserved
                    pendingScrollToID = preserved
                }
                // Allow any scroll animation to settle before resuming anchor updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    jumpInProgress = false
                }
            }
        )
        .fullScreenCover(item: $imageViewer) { (selection: ImageViewerState) in
            ImageViewer(post: selection.post, startIndex: selection.index)
        }
        #if canImport(SafariServices) && canImport(UIKit)
        .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
            if let url = safariURL { SafariView(url: url) }
        }
        .onChange(of: anchorID) { old, new in
            if !didInitialRestore || jumpInProgress || isLoading { return }
            guard let new, new != old else { return }
            updateAnchorPostID(new)
        }
        #endif
        .navigationDestination(item: $postSelection) { post in
            PostDetailView(post: post)
        }
        .onChange(of: postSelection) { _, newValue in
            if newValue != nil {
                // Suppress anchor updates when navigating to a post
                suppressAnchorUpdates = true
            } else {
                // Re-enable anchor updates after a delay when returning from post detail
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    suppressAnchorUpdates = false
                }
            }
        }
        .navigationDestination(item: $profileRoute) { route in
            ProfileView(network: route.network, handle: route.handle)
        }
        .onChange(of: profileRoute) { _, newValue in
            if newValue != nil {
                // Suppress anchor updates when navigating to a profile
                suppressAnchorUpdates = true
            } else {
                // Re-enable anchor updates after a delay when returning from profile
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    suppressAnchorUpdates = false
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if aboveCount > 0 {
                Button {
                    if let topID = posts.first?.id {
                        pendingScrollToID = topID
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                        Text("\(aboveCount)")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
        }
        .overlay(alignment: .bottom) {
            if let t = toastText {
                HStack(spacing: 8) {
                    Text(t)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                    Button {
                        withAnimation { toastText = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss message")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                // Lift above bottom FABs (≈ 52 size + 16 padding + gap)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Profile avatar with quick actions
                Menu {
                    Button("View Profile") { showMyProfiles = true }
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Divider()
                    Button("🔄 Force Refresh Timeline") {
                        Task { await debugClearAndReload() }
                    }
                } label: {
                    AvatarCircle(
                        handle: session.selectedHandle ?? "?",
                        url: session.selectedAvatarURL,
                        size: 28
                    )
                    .accessibilityLabel("Profile")
                }
            }
        }
        .navigationDestination(isPresented: $showMyProfiles) {
            MyProfilesView()
        }
        .task {
            // Only run restoration logic if we haven't done initial restore yet
            guard !didInitialRestore else { return }

            let restoredAnchor = await loadPersisted()
            if let anchor = restoredAnchor {
                // Apply anchor immediately and trigger instant scroll
                anchorID = anchor
                DispatchQueue.main.async { pendingScrollToID = anchor }
                // Mark restore complete after scroll settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    didInitialRestore = true
                }
            } else {
                // No anchor to restore, fetch fresh content
                await refresh()
                didInitialRestore = true
            }
        }
        .onChange(of: filter) { _, _ in
            Task { await applyFilterAsync() }
            // When switching filters, jump to top of the new dataset
            if let topID = posts.first?.id {
                anchorID = topID
                pendingScrollToID = topID
            }
        }
        .onChange(of: error) { _, new in
            guard let msg = new, !msg.isEmpty else { return }
            Haptics.notify(.error)
            withAnimation { toastText = msg }
        }
    }
}

struct TimelineList: View {
    let posts: [UnifiedPost]
    let isLoadingMore: Bool
    let session: SessionStore
    let onItemAppear: (Int) -> Void
    let onOpenPost: (UnifiedPost) -> Void
    @Binding var anchorID: String?
    @Binding var pendingScrollToID: String?
    @Binding var jumpInProgress: Bool
    @Binding var suppressAnchorUpdates: Bool
    let didInitialRestore: Bool
    let onOpenProfile: (Network, String) -> Void
    let onTapImage: (UnifiedPost, Int) -> Void
    let onOpenExternalURL: (URL) -> Void
    let onRefresh: () async -> Void

    @State private var visibleTracker = VisibleRangeTracker()

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(posts.indices, id: \.self) { index in
                    let post = posts[index]
                    TimelineRow(
                        post: post,
                        session: session,
                        onOpenPost: onOpenPost,
                        onOpenProfile: onOpenProfile,
                        onTapImage: onTapImage,
                        onOpenExternalURL: onOpenExternalURL
                    )
                    .id(post.id)
                    .onAppear {
                        onItemAppear(index)
                        applyAnchorCandidate(visibleTracker.appeared(id: post.id, index: index))
                    }
                    .onDisappear {
                        applyAnchorCandidate(visibleTracker.disappeared(id: post.id))
                    }
                }

                if isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 12)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .scrollIndicators(.automatic)
            .applyScrollTargetLayoutIfAvailable()
            .refreshable { await onRefresh() }
            .scrollPosition(id: $anchorID)
            .transaction { if !jumpInProgress { $0.animation = nil } }
            .onChange(of: pendingScrollToID) { _, new in
                guard let id = new else { return }
                jumpInProgress = true

                // Use instant scroll for initial restore, animated for user interactions
                if didInitialRestore {
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
                } else {
                    // Instant scroll for initial restore
                    proxy.scrollTo(id, anchor: .top)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    jumpInProgress = false
                    applyAnchorCandidate(visibleTracker.currentAnchorID())
                }
                pendingScrollToID = nil
            }
            .onChange(of: posts.count) { _, _ in
                visibleTracker.prune(validIDs: posts.map { $0.id })
                applyAnchorCandidate(visibleTracker.currentAnchorID())
            }
            .onChange(of: jumpInProgress) { _, newValue in
                if !newValue {
                    applyAnchorCandidate(visibleTracker.currentAnchorID())
                }
            }
        }
    }
}

private struct ScrollTargetLayoutSupport: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollTargetLayout()
        } else {
            content
        }
    }
}

private extension View {
    func applyScrollTargetLayoutIfAvailable() -> some View {
        modifier(ScrollTargetLayoutSupport())
    }
}

private struct VisibleRangeTracker {
    private var indexByID: [String: Int] = [:]

    mutating func appeared(id: String, index: Int) -> String? {
        indexByID[id] = index
        return currentAnchorID()
    }

    mutating func disappeared(id: String) -> String? {
        indexByID.removeValue(forKey: id)
        return currentAnchorID()
    }

    mutating func prune(validIDs: [String]) {
        guard !indexByID.isEmpty else { return }
        let allowed = Set(validIDs)
        indexByID = Dictionary(uniqueKeysWithValues: indexByID.lazy.filter { allowed.contains($0.key) })
    }

    func currentAnchorID() -> String? {
        // Choose the post that would be most appropriate as a visual anchor
        // This should be the post that appears near the top of the visible area
        guard !indexByID.isEmpty else { return nil }

        // Find the post with the minimum index (topmost in the feed)
        // But bias towards posts that are more likely to be fully visible
        let sortedByIndex = indexByID.sorted { $0.value < $1.value }

        // If we have multiple visible posts, prefer one that's likely to be
        // more prominently visible rather than just the first one
        if sortedByIndex.count >= 2 {
            // Use the second post if it exists, as it's more likely to be
            // the one the user perceives as "at the top" of their view
            return sortedByIndex[1].key
        } else {
            // Fall back to the first post if that's all we have
            return sortedByIndex.first?.key
        }
    }
}

private extension TimelineList {
    func applyAnchorCandidate(_ candidate: String?) {
        guard !jumpInProgress && !suppressAnchorUpdates else { return }
        if anchorID != candidate { anchorID = candidate }
    }
}

private extension HomeTimelineView {
    enum CanonicalPreference: String, CaseIterable { case newest, oldest, blueskyFirst, mastodonFirst }

    // MARK: - Public API used by the view

    /// Incrementally fetches new items above the current top without reloading/reshuffling existing items.
    @MainActor
    func refresh() async {
        if isLoading { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        @Sendable func fetchMastodonNew() async -> Result<(newPosts: [UnifiedPost], newestID: String?), Error> {
            guard let client = session.mastodonClient else { return .success(([], mastodonNewestID)) }
            do {
                let sinceID = mastodonNewestID ?? topMastodonID()
                if let sinceID {
                    let new = try await client.fetchHomeTimelineSince(sinceID: sinceID)
                    let newest = new.first.flatMap { Self.extractMastodonID(from: $0.id) } ?? sinceID
                    return .success((new, newest))
                } else {
                    let (page, _) = try await client.fetchHomeTimeline(cursor: nil)
                    return .success((page, page.first.flatMap { Self.extractMastodonID(from: $0.id) }))
                }
            } catch { return .failure(error) }
        }

        @Sendable func fetchBlueskyNew() async -> Result<(newPosts: [UnifiedPost], nextCursor: String?), Error> {
            guard let client = session.blueskyClient else { return .success(([], blueskyBottomCursor)) }
            do {
                var collected: [UnifiedPost] = []
                var cursor: String? = nil
                var pages = 0
                let maxPages = 4
                var stop = false
                while !stop {
                    let (batch, next) = try await client.fetchHomeTimeline(cursor: cursor)
                    for p in batch {
                        if idSet.contains(p.id) { stop = true; break }
                        collected.append(p)
                    }
                    cursor = next
                    pages += 1
                    if stop || cursor == nil || pages >= maxPages { break }
                }
                return .success((collected, blueskyBottomCursor))
            } catch {
                if case BlueskyClient.APIError.badStatus(let code, _) = error, code == 401 {
                    if await session.refreshBlueskyIfNeeded(), let client2 = session.blueskyClient {
                        do {
                            var collected: [UnifiedPost] = []
                            var cursor: String? = nil
                            var pages = 0
                            let maxPages = 4
                            var stop = false
                            while !stop {
                                let (batch, next) = try await client2.fetchHomeTimeline(cursor: cursor)
                                for p in batch {
                                    if idSet.contains(p.id) { stop = true; break }
                                    collected.append(p)
                                }
                                cursor = next
                                pages += 1
                                if stop || cursor == nil || pages >= maxPages { break }
                            }
                            return .success((collected, blueskyBottomCursor))
                        } catch {
                            session.signOutBluesky()
                            return .failure(error)
                        }
                    } else {
                        session.signOutBluesky()
                        return .failure(error)
                    }
                }
                return .failure(error)
            }
        }

        async let mastodonTask = fetchMastodonNew()
        async let blueskyTask = fetchBlueskyNew()

        let mResult = await mastodonTask
        let bResult = await blueskyTask

        // Merge incremental results and sort by creation time
        var newPosts: [UnifiedPost] = []
        if case .success(let (mNew, newestID)) = mResult {
            if let newestID { mastodonNewestID = newestID }
            newPosts.append(contentsOf: mNew)
        }
        if case .success(let (bNew, _)) = bResult {
            newPosts.append(contentsOf: bNew)
        }

        // Sort all new posts by creation time (newest first) to create proper interleaved timeline
        newPosts.sort { $0.createdAt > $1.createdAt }

        if !newPosts.isEmpty {
            await processAndInsertNewPosts(newPosts)
        }

        // Surface an error if either provider failed, with source labels
        var messages: [String] = []
        if case .failure(let mErr) = mResult {
            let msg = (mErr as? LocalizedError)?.errorDescription ?? mErr.localizedDescription
            messages.append("Mastodon: \(msg)")
        }
        if case .failure(let bErr) = bResult {
            let msg = (bErr as? LocalizedError)?.errorDescription ?? bErr.localizedDescription
            messages.append("Bluesky: \(msg)")
        }
        if !messages.isEmpty {
            self.error = messages.joined(separator: "\n")
            print("[Timeline] refresh errors ->\n\(self.error!)")
        }
    }

    @MainActor
    func onItemAppear(index: Int) {
        let threshold = 5
        guard index >= posts.count - threshold else { return }
        Task { await loadMore() }
    }

    @MainActor
    func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        error = nil
        defer { isLoadingMore = false }

        var fetched: [UnifiedPost] = []

        // Older Mastodon page using max_id
        if let client = session.mastodonClient {
            do {
                let (page, next) = try await client.fetchHomeTimeline(cursor: mastodonBottomCursor)
                mastodonBottomCursor = next ?? mastodonBottomCursor
                fetched.append(contentsOf: page)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.error = "Mastodon: \(msg)"
                print("[Timeline] loadMore mastodon error: \(msg)")
            }
        }

        // Older Bluesky page using cursor
        if let client = session.blueskyClient {
            do {
                let (page, next) = try await client.fetchHomeTimeline(cursor: blueskyBottomCursor)
                blueskyBottomCursor = next ?? blueskyBottomCursor
                fetched.append(contentsOf: page)
            } catch {
                if case BlueskyClient.APIError.badStatus(let code, _) = error, code == 401 {
                    if await session.refreshBlueskyIfNeeded(), let client2 = session.blueskyClient,
                       let (page, next) = try? await client2.fetchHomeTimeline(cursor: blueskyBottomCursor) {
                        blueskyBottomCursor = next ?? blueskyBottomCursor
                        fetched.append(contentsOf: page)
                    } else { session.signOutBluesky() }
                    let msg = (error as? LocalizedError)?.errorDescription ?? "Unauthorized"
                    self.error = "Bluesky: \(msg)"
                    print("[Timeline] loadMore bluesky 401/error: \(msg)")
                } else {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.error = "Bluesky: \(msg)"
                    print("[Timeline] loadMore bluesky error: \(msg)")
                }
            }
        }

        if !fetched.isEmpty {
            // Sort older posts by creation time (newest first) for proper interleaving
            fetched.sort { $0.createdAt > $1.createdAt }
            await processAndInsertOlderPosts(fetched)
        }
    }

    // MARK: - Persistence
    @MainActor
    func loadPersisted() async -> String? {
        if let saved = TimelinePersistence.load() {
            let deduped = Normalizer.dedupe(saved.posts)
            allPosts = deduped
            idSet = Set(deduped.map { $0.id })
            mastodonBottomCursor = saved.meta.mastodonBottomCursor
            blueskyBottomCursor = saved.meta.blueskyBottomCursor
            mastodonNewestID = saved.meta.mastodonNewestID
            currentAnchorID = saved.meta.anchorPostID
            let didTrim = compactIfNeeded(anchorID: saved.meta.anchorPostID)
            if deduped.count != saved.posts.count || didTrim {
                persist(anchorID: saved.meta.anchorPostID)
            }
            await applyFilterAsync()
            return saved.meta.anchorPostID
        }
        await applyFilterAsync()
        return nil
    }

    @MainActor
    func updateAnchorPostID(_ id: String?) {
        currentAnchorID = id
        persist()
    }

    @MainActor
    func debugClearAndReload() async {
        // Clear all cached data
        allPosts.removeAll()
        idSet.removeAll()
        posts.removeAll()

        // Reset pagination cursors
        mastodonBottomCursor = nil
        blueskyBottomCursor = nil
        mastodonNewestID = nil
        currentAnchorID = nil

        // Clear cached filters
        invalidateFilterCache()

        // Load fresh data
        await refresh()
    }

    @MainActor
    private func persist(anchorID: String? = nil) {
        let anchor = anchorID ?? currentAnchorID
        // Compact before saving to bound storage
        let didCompact = compactIfNeeded(anchorID: anchor)
        if didCompact { Task { await applyFilterAsync() } }
        let meta = TimelineMeta(
            mastodonBottomCursor: mastodonBottomCursor,
            blueskyBottomCursor: blueskyBottomCursor,
            mastodonNewestID: mastodonNewestID,
            anchorPostID: anchor,
            lastSaved: Date()
        )
        TimelinePersistence.save(posts: allPosts, meta: meta)
    }

    // Trim oldest items to keep the file small and startup fast, preserving anchor and recent items.
    // Strategy: if count > high water, trim to maxCount; always keep items newer than age window; protect ±buffer around anchor.
    @MainActor
    private func compactIfNeeded(anchorID: String?) -> Bool {
        let count = allPosts.count
        if count <= retentionHighWater { return false }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionAgeDays, to: Date()) ?? Date.distantPast
        var keep = Array(repeating: false, count: count)

        // Decide base policy: keep last N or keep last X days (whichever is smaller)
        let head = min(retentionMaxCount, count)
        let ageCount = allPosts.prefix { $0.createdAt >= cutoff }.count
        let useAge = ageCount > 0 && ageCount < head
        if useAge {
            // Keep all posts newer than cutoff
            for (i, p) in allPosts.enumerated() where p.createdAt >= cutoff { keep[i] = true }
        } else {
            // Keep recent head up to retentionMaxCount
            if head > 0 { for i in 0..<head { keep[i] = true } }
        }

        // Protect around anchor
        if let anchorID, let idx = allPosts.firstIndex(where: { $0.id == anchorID }) {
            let start = max(0, idx - retentionAnchorBuffer)
            let end = min(count - 1, idx + retentionAnchorBuffer)
            if start <= end { for i in start...end { keep[i] = true } }
        }

        // If we wouldn't trim anything, bail
        if !keep.contains(false) { return false }

        // Build trimmed list
        var trimmed: [UnifiedPost] = []
        trimmed.reserveCapacity(min(count, retentionMaxCount + (retentionAnchorBuffer * 2) + 512))
        for (i, p) in allPosts.enumerated() where keep[i] { trimmed.append(p) }

        // Only commit if it actually reduces size significantly (to avoid churning)
        if trimmed.count >= allPosts.count { return false }
        allPosts = trimmed
        idSet = Set(allPosts.map { $0.id })
        invalidateFilterCache()
        return true
    }

    // MARK: - Background Processing

    @MainActor
    private func processAndInsertNewPosts(_ newPosts: [UnifiedPost]) async {
        // For now, skip heavy processing and just insert directly
        // This maintains the performance improvement from cached filtering
        insertNewAtTop(newPosts)
        invalidateFilterCache()
        await applyFilterAsync()
        persist()
    }

    @MainActor
    private func processAndInsertOlderPosts(_ olderPosts: [UnifiedPost]) async {
        // For now, skip heavy processing and just insert directly
        // This maintains the performance improvement from cached filtering
        insertOlderInOrder(olderPosts)
        invalidateFilterCache()
        await applyFilterAsync()
        persist()
    }

    @MainActor
    private func invalidateFilterCache() {
        filterCacheValid = false
    }

    @MainActor
    func applyFilterAsync() async {
        // Use cached results if available and valid
        if filterCacheValid {
            switch filter {
            case .all:
                posts = cachedAllPosts
            case .bluesky:
                posts = cachedBlueskyPosts
            case .mastodon:
                posts = cachedMastodonPosts
            }
            return
        }

        // Process filtering in background
        let allPostsCopy = allPosts
        let (allFiltered, blueskyFiltered, mastodonFiltered) = await Task.detached {
            let bluesky = allPostsCopy.filter { if case .bluesky = $0.network { return true } else { return false } }
            let mastodon = allPostsCopy.filter { if case .mastodon = $0.network { return true } else { return false } }

            return (allPostsCopy, bluesky, mastodon)
        }.value

        // Update cache
        cachedAllPosts = allFiltered
        cachedBlueskyPosts = blueskyFiltered
        cachedMastodonPosts = mastodonFiltered
        filterCacheValid = true

        // Apply current filter
        switch filter {
        case .all:
            posts = allFiltered
        case .bluesky:
            posts = blueskyFiltered
        case .mastodon:
            posts = mastodonFiltered
        }
    }

    // MARK: - Thread Grouping
    private func groupIntoThreads(_ allPosts: [UnifiedPost]) -> [UnifiedPost] {
        var result: [UnifiedPost] = []
        var usedPostIDs: Set<String> = []

        // Sort by creation time (newest first for initial processing)
        let sortedPosts = allPosts.sorted { $0.createdAt > $1.createdAt }

        // Find all conversation clusters
        let conversationClusters = findConversationClusters(in: sortedPosts)

        for cluster in conversationClusters {
            if cluster.posts.contains(where: { usedPostIDs.contains($0.id) }) {
                continue // Already processed
            }

            if cluster.posts.count > 1 {
                // This is a thread/conversation
                let rootPost = cluster.rootPost
                let replies = cluster.posts.filter { $0.id != rootPost.id }
                let sortedReplies = replies.sorted { $0.createdAt > $1.createdAt }

                var rootWithPreview = rootPost
                let recentReplies = Array(sortedReplies.prefix(2))
                let participants = Set(cluster.posts.map { $0.authorHandle })
                let newestDate = cluster.posts.max(by: { $0.createdAt < $1.createdAt })?.createdAt ?? rootPost.createdAt

                rootWithPreview.threadPreview = ThreadPreview(
                    recentReplies: recentReplies,
                    totalReplyCount: replies.count,
                    hasMoreReplies: replies.count > 2,
                    newestPostDate: newestDate,
                    conversationParticipants: participants
                )

                result.append(rootWithPreview)

                // Mark all posts in this conversation as used
                for post in cluster.posts {
                    usedPostIDs.insert(post.id)
                }
            } else {
                // Standalone post
                let post = cluster.posts[0]
                if !usedPostIDs.contains(post.id) {
                    result.append(post)
                    usedPostIDs.insert(post.id)
                }
            }
        }

        // Sort final result by newest post in each thread for timeline positioning
        return result.sorted { lhs, rhs in
            let lhsNewest = lhs.threadPreview?.newestPostDate ?? lhs.createdAt
            let rhsNewest = rhs.threadPreview?.newestPostDate ?? rhs.createdAt
            return lhsNewest > rhsNewest
        }
    }

    private struct ConversationCluster {
        let posts: [UnifiedPost]
        let rootPost: UnifiedPost
    }

    private func findConversationClusters(in posts: [UnifiedPost]) -> [ConversationCluster] {
        var clusters: [ConversationCluster] = []
        var processedIDs: Set<String> = []

        // First, find traditional reply threads
        for post in posts {
            if processedIDs.contains(post.id) { continue }

            if post.inReplyToID != nil {
                // This is a reply - find its complete thread
                let (rootPost, threadPosts) = extractThread(for: post, from: posts)
                if !processedIDs.contains(rootPost.id) {
                    clusters.append(ConversationCluster(posts: threadPosts, rootPost: rootPost))
                    for threadPost in threadPosts {
                        processedIDs.insert(threadPost.id)
                    }
                }
            } else {
                // Check if this root has replies
                let allInThread = findAllInThread(rootID: post.id, allPosts: posts)
                clusters.append(ConversationCluster(posts: allInThread, rootPost: post))
                for threadPost in allInThread {
                    processedIDs.insert(threadPost.id)
                }
            }
        }

        // Now, find conversation clusters between multiple users
        clusters = mergeConversationClusters(clusters)

        return clusters
    }

    private func mergeConversationClusters(_ initialClusters: [ConversationCluster]) -> [ConversationCluster] {
        var clusters = initialClusters
        let conversationWindow: TimeInterval = 30 * 60 // 30 minutes
        let maxClusterSize = 10 // Prevent extremely large clusters

        var didMerge = true
        while didMerge {
            didMerge = false

            for i in 0..<clusters.count {
                for j in (i+1)..<clusters.count {
                    let cluster1 = clusters[i]
                    let cluster2 = clusters[j]

                    // Skip if clusters are too large
                    if cluster1.posts.count + cluster2.posts.count > maxClusterSize {
                        continue
                    }

                    // Check if these clusters represent a conversation
                    if shouldMergeClusters(cluster1, cluster2, timeWindow: conversationWindow) {
                        // Merge cluster2 into cluster1
                        let mergedPosts = (cluster1.posts + cluster2.posts).sorted { $0.createdAt < $1.createdAt }
                        let earliestPost = mergedPosts.first ?? cluster1.rootPost

                        clusters[i] = ConversationCluster(posts: mergedPosts, rootPost: earliestPost)
                        clusters.remove(at: j)
                        didMerge = true
                        break
                    }
                }
                if didMerge { break }
            }
        }

        return clusters
    }

    private func shouldMergeClusters(_ cluster1: ConversationCluster, _ cluster2: ConversationCluster, timeWindow: TimeInterval) -> Bool {
        // Get unique participants from both clusters
        let participants1 = Set(cluster1.posts.map { $0.authorHandle })
        let participants2 = Set(cluster2.posts.map { $0.authorHandle })

        // Check for overlapping participants
        let hasCommonParticipants = !participants1.isDisjoint(with: participants2)

        if !hasCommonParticipants {
            return false
        }

        // Check time proximity
        let allPosts = cluster1.posts + cluster2.posts
        let sortedByTime = allPosts.sorted { $0.createdAt < $1.createdAt }

        // Check if posts are within the conversation window
        for i in 0..<(sortedByTime.count - 1) {
            let timeDiff = sortedByTime[i + 1].createdAt.timeIntervalSince(sortedByTime[i].createdAt)
            if timeDiff > timeWindow {
                // If there's a large gap, only merge if there are replies crossing the gap
                let beforeGap = Set(sortedByTime[0...i].map { $0.id })

                // Check if any post after the gap replies to a post before the gap
                let hasReplyAcrossGap = sortedByTime[(i+1)...].contains { post in
                    guard let replyToID = post.inReplyToID else { return false }
                    return beforeGap.contains(replyToID)
                }

                if !hasReplyAcrossGap {
                    return false
                }
            }
        }

        return true
    }

    private func extractThread(for post: UnifiedPost, from allPosts: [UnifiedPost]) -> (root: UnifiedPost, thread: [UnifiedPost]) {
        // Find the root post by following inReplyToID chain
        var current = post
        var seen: Set<String> = [post.id]

        while let replyToID = current.inReplyToID,
              let parent = allPosts.first(where: { $0.id == replyToID }),
              !seen.contains(parent.id) {
            current = parent
            seen.insert(parent.id)
        }

        let rootPost = current

        // Find all posts in this thread
        let threadPosts = findAllInThread(rootID: rootPost.id, allPosts: allPosts)

        return (rootPost, threadPosts)
    }

    private func findRepliesTo(postID: String, in allPosts: [UnifiedPost]) -> [UnifiedPost] {
        return allPosts.filter { $0.inReplyToID == postID }.sorted { $0.createdAt > $1.createdAt }
    }

    private func findAllInThread(rootID: String, allPosts: [UnifiedPost]) -> [UnifiedPost] {
        var result: [UnifiedPost] = []
        var toProcess: [String] = [rootID]
        var processed: Set<String> = []

        while !toProcess.isEmpty {
            let currentID = toProcess.removeFirst()
            if processed.contains(currentID) { continue }
            processed.insert(currentID)

            if let post = allPosts.first(where: { $0.id == currentID }) {
                result.append(post)

                // Find direct replies to this post
                let replies = allPosts.filter { $0.inReplyToID == currentID }
                for reply in replies {
                    if !processed.contains(reply.id) {
                        toProcess.append(reply.id)
                    }
                }
            }
        }

        return result.sorted { $0.createdAt < $1.createdAt } // Chronological order within thread
    }

    // MARK: - Cross-post de-duplication
    // Expand window to better catch delayed cross-posts across services
    private var crossPostWindow: TimeInterval { 6 * 60 * 60 }

    private func dedupeCrossPosts(_ all: [UnifiedPost],
                                  preference: CanonicalPreference) -> [UnifiedPost] {
        // Group by a conservative signature: author local handle + normalized text + media hint
        var buckets: [String: [UnifiedPost]] = [:]
        for p in all {
            let key = crossSignature(for: p)
            buckets[key, default: []].append(p)
        }

        var out: [UnifiedPost] = []
        for (_, group) in buckets {
            // Sort by time and create clusters within the window
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            // Use a shorter window for link-only bodies to avoid over-merging
            let bodyForWindow = normalizeBody(sorted.first?.text ?? AttributedString(""))
            let window = bodyForWindow.isEmpty ? min(crossPostWindow, 90 * 60) : crossPostWindow
            var cluster: [UnifiedPost] = []
            var anchor: UnifiedPost?

            func flushCluster() {
                guard !cluster.isEmpty else { return }
                out.append(selectCanonical(from: cluster, preference: preference))
                cluster.removeAll()
                anchor = nil
            }

            for post in sorted {
                if let a = anchor {
                    if abs(post.createdAt.timeIntervalSince(a.createdAt)) <= window {
                        cluster.append(post)
                    } else {
                        flushCluster()
                        cluster.append(post)
                        anchor = post
                    }
                } else {
                    cluster.append(post)
                    anchor = post
                }
            }
            flushCluster()
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    private func selectCanonical(from cluster: [UnifiedPost],
                                 preference: CanonicalPreference) -> UnifiedPost {
        guard cluster.count > 1 else { return cluster[0] }

        // First, prefer posts that have media (any posts with non-empty media arrays)
        let postsWithMedia = cluster.filter { !$0.media.isEmpty }

        // If we have posts with media, prefer those; otherwise use all posts
        let withValidMedia = postsWithMedia.isEmpty ? cluster : postsWithMedia

        // If some posts have valid media and others don't, prefer those with valid media
        let candidates = withValidMedia.isEmpty ? cluster : withValidMedia

        let pick: UnifiedPost = {
            switch preference {
            case .blueskyFirst:
                return candidates.first(where: { if case .bluesky = $0.network { return true } else { return false } })
                    ?? candidates.max(by: { $0.createdAt < $1.createdAt })!
            case .mastodonFirst:
                return candidates.first(where: { if case .mastodon = $0.network { return true } else { return false } })
                    ?? candidates.max(by: { $0.createdAt < $1.createdAt })!
            case .newest:
                return candidates.max(by: { $0.createdAt < $1.createdAt })!
            case .oldest:
                return candidates.min(by: { $0.createdAt < $1.createdAt })!
            }
        }()

        var canonical = pick
        canonical.isCrossPostCanonical = true

        var alts: [Network: String] = [:]
        for p in cluster where p.id != pick.id {
            alts[p.network] = p.id
        }
        canonical.crossPostAlternates = alts.isEmpty ? nil : alts
        return canonical
    }

    private func crossSignature(for p: UnifiedPost) -> String {
        let author = authorKey(p)
        let body = normalizeBody(p.text)
        let mediaCount = p.media.count // robust across services (ignores differing CDN filenames)
        return "\(author)|\(body)|n\(mediaCount)"
    }

    // Try to map an author's handle across services to a stable local username
    private func authorKey(_ p: UnifiedPost) -> String {
        let handle = p.authorHandle.lowercased()
        var local = handle
        if let atIndex = handle.firstIndex(of: "@") {
            // Mastodon: acct may be "user" or "user@instance" → take local part
            local = String(handle[..<atIndex])
        } else if handle.contains(".") {
            // Bluesky: handle like "user.bsky.social" → take first label
            local = String(handle.split(separator: ".").first ?? Substring(handle))
        }
        return local.replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }

    private func normalizeAuthor(_ p: UnifiedPost) -> String {
        let base = (p.authorDisplayName?.isEmpty == false ? p.authorDisplayName! : p.authorHandle)
        return base
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }

    private func normalizeBody(_ a: AttributedString) -> String {
        var s = String(a.characters).lowercased()
        // Strip links entirely so shortened vs full URLs match
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        // Remove any common URL-like tokens that might slip through (e.g., www.example.com)
        s = s.replacingOccurrences(of: #"\b(?:www\.)?[-a-z0-9@:%._+~#=]{2,256}\.[a-z]{2,63}\b[^\s]*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<!\w)[@#][\p{L}0-9_.-]+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mediaHint(_ p: UnifiedPost) -> String {
        // Use only the count to avoid CDN filename/host differences across services
        return p.media.isEmpty ? "-" : "n\(p.media.count)"
    }

    // MARK: - Restore helpers
    @MainActor
    func ensureContains(postID: String, maxPages: Int = 6) async {
        if idSet.contains(postID) { return }
        var pages = 0
        while pages < maxPages {
            await loadMore()
            if idSet.contains(postID) { return }
            if mastodonBottomCursor == nil && blueskyBottomCursor == nil { break }
            pages += 1
        }
    }

    // MARK: - Insertion helpers (stable ordering)
    @MainActor
    private func insertNewAtTop(_ batch: [UnifiedPost]) {
        guard !batch.isEmpty else { return }
        // Filter out duplicates by id and cross-post signature
        let filtered = batch.filter { p in
            guard !idSet.contains(p.id) else { return false }
            return !isCrossDuplicate(of: p)
        }
        guard !filtered.isEmpty else { return }
        allPosts.insert(contentsOf: filtered, at: 0)
        for p in filtered { idSet.insert(p.id) }
        invalidateFilterCache()
    }

    @MainActor
    private func insertOlderInOrder(_ batch: [UnifiedPost]) {
        var didInsert = false
        for p in batch {
            if idSet.contains(p.id) { continue }
            if isCrossDuplicate(of: p) { continue }
            let idx = insertionIndex(for: p)
            allPosts.insert(p, at: idx)
            idSet.insert(p.id)
            didInsert = true
        }
        if didInsert {
            invalidateFilterCache()
        }
    }

    // Binary search by createdAt (newest → oldest)
    private func insertionIndex(for p: UnifiedPost) -> Int {
        var low = 0
        var high = allPosts.count
        while low < high {
            let mid = (low + high) / 2
            let m = allPosts[mid]
            if p.createdAt > m.createdAt {
                high = mid
            } else if p.createdAt < m.createdAt {
                low = mid + 1
            } else {
                // Stable tie-breaker on id
                if p.id < m.id { high = mid } else { low = mid + 1 }
            }
        }
        return low
    }

    private func isCrossDuplicate(of p: UnifiedPost) -> Bool {
        // Use the same signature + time window as the batch de-duper to detect duplicates among existing posts
        let sig = crossSignature(for: p)
        // Scan a narrow window around where this would be inserted
        let window: TimeInterval = crossPostWindow
        // Find neighbors within time window
        let idx = insertionIndex(for: p)
        var i = idx
        while i > 0 {
            i -= 1
            let q = allPosts[i]
            if abs(q.createdAt.timeIntervalSince(p.createdAt)) > window { break }
            if crossSignature(for: q) == sig {
                // Update alternates if helpful
                var existing = allPosts[i]
                var alts = existing.crossPostAlternates ?? [:]
                if alts[p.network] == nil { alts[p.network] = p.id; existing.crossPostAlternates = alts; allPosts[i] = existing }
                return true
            }
        }
        var j = idx
        while j < allPosts.count {
            let q = allPosts[j]
            if abs(q.createdAt.timeIntervalSince(p.createdAt)) > window { break }
            if crossSignature(for: q) == sig {
                var existing = allPosts[j]
                var alts = existing.crossPostAlternates ?? [:]
                if alts[p.network] == nil { alts[p.network] = p.id; existing.crossPostAlternates = alts; allPosts[j] = existing }
                return true
            }
            j += 1
        }
        return false
    }

    private func topMastodonID() -> String? {
        for p in allPosts {
            if case .mastodon = p.network, let id = Self.extractMastodonID(from: p.id) { return id }
        }
        return nil
    }

    private static func extractMastodonID(from unifiedID: String) -> String? {
        // unified id format: "mastodon:<id>"
        guard let idx = unifiedID.firstIndex(of: ":") else { return nil }
        return String(unifiedID[unifiedID.index(after: idx)...])
    }
}
