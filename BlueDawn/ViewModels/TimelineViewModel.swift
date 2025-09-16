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

    enum CanonicalPreference: String, CaseIterable { case newest, oldest, blueskyFirst, mastodonFirst }
    var canonicalPreference: CanonicalPreference = .newest

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

        func fetchMastodonWrapper() async -> Result<([UnifiedPost], String?), Error> {
            do { return .success(try await snapshotMastodon(resetCursor: true)) }
            catch { return .failure(error) }
        }

        func fetchBlueskyWrapper() async -> Result<([UnifiedPost], String?), Error> {
            do { return .success(try await snapshotBluesky(resetCursor: true)) }
            catch { return .failure(error) }
        }

        let mResult = await fetchMastodonWrapper()
        var bResult = await fetchBlueskyWrapper()

        if case .failure(let bError) = bResult,
           case BlueskyClient.APIError.badStatus(let code, _) = bError, code == 401 {
            if await session.refreshBlueskyIfNeeded() {
                bResult = await fetchBlueskyWrapper()
            } else {
                session.signOutBluesky()
            }
        }

        var nextMPosts = mastodonPosts
        var nextMCur = mastodonCursor
        var nextBPosts = blueskyPosts
        var nextBCur = blueskyCursor

        if case .success(let r) = mResult { nextMPosts = r.0; nextMCur = r.1 }
        if case .success(let r) = bResult { nextBPosts = r.0; nextBCur = r.1 }

        mastodonPosts = nextMPosts
        mastodonCursor = nextMCur
        blueskyPosts = nextBPosts
        blueskyCursor = nextBCur

        applyFilter()

        if case .failure = mResult, case .failure(let bErr) = bResult {
            self.error = (bErr as? LocalizedError)?.errorDescription ?? bErr.localizedDescription
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

        func fetchMastodonWrapper() async -> Result<([UnifiedPost], String?), Error> {
            do { return .success(try await snapshotMastodon(resetCursor: false)) }
            catch { return .failure(error) }
        }

        func fetchBlueskyWrapper() async -> Result<([UnifiedPost], String?), Error> {
            do { return .success(try await snapshotBluesky(resetCursor: false)) }
            catch { return .failure(error) }
        }

        let mResult = await fetchMastodonWrapper()
        var bResult = await fetchBlueskyWrapper()

        if case .failure(let bError) = bResult,
           case BlueskyClient.APIError.badStatus(let code, _) = bError, code == 401 {
            if await session.refreshBlueskyIfNeeded() {
                bResult = await fetchBlueskyWrapper()
            } else {
                session.signOutBluesky()
            }
        }

        var nextMPosts = mastodonPosts
        var nextMCur = mastodonCursor
        var nextBPosts = blueskyPosts
        var nextBCur = blueskyCursor

        if case .success(let r) = mResult { nextMPosts = r.0; nextMCur = r.1 }
        if case .success(let r) = bResult { nextBPosts = r.0; nextBCur = r.1 }

        mastodonPosts = nextMPosts
        mastodonCursor = nextMCur
        blueskyPosts = nextBPosts
        blueskyCursor = nextBCur

        applyFilter()

        if case .failure = mResult, case .failure(let bErr) = bResult {
            self.error = (bErr as? LocalizedError)?.errorDescription ?? bErr.localizedDescription
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

    // Snapshot fetchers: build the post array without mutating state, so we can swap atomically.
    private func snapshotMastodon(resetCursor: Bool) async throws -> ([UnifiedPost], String?) {
        guard let client = session.mastodonClient else { return (mastodonPosts, mastodonCursor) }
        let startCursor = resetCursor ? nil : mastodonCursor
        let base = resetCursor ? [] : mastodonPosts
        let (newPosts, next) = try await client.fetchHomeTimeline(cursor: startCursor)
        return (base + newPosts, next)
    }

    private func snapshotBluesky(resetCursor: Bool) async throws -> ([UnifiedPost], String?) {
        guard let client = session.blueskyClient else { return (blueskyPosts, blueskyCursor) }
        let startCursor = resetCursor ? nil : blueskyCursor
        let base = resetCursor ? [] : blueskyPosts
        let (newPosts, next) = try await client.fetchHomeTimeline(cursor: startCursor)
        return (base + newPosts, next)
    }

    private func applyFilter() {
        switch filter {
        case .all:
            let merged = mastodonPosts + blueskyPosts
            posts = groupIntoThreads(dedupeCrossPosts(merged, preference: canonicalPreference))
        case .bluesky:
            posts = groupIntoThreads(blueskyPosts.sorted { $0.createdAt > $1.createdAt })
        case .mastodon:
            posts = groupIntoThreads(mastodonPosts.sorted { $0.createdAt > $1.createdAt })
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
    private let crossPostWindow: TimeInterval = 30 * 60 // 30 minutes

    private func dedupeCrossPosts(_ all: [UnifiedPost],
                                  preference: CanonicalPreference) -> [UnifiedPost] {
        // Group by a conservative signature: author + normalized text + media hint
        var buckets: [String: [UnifiedPost]] = [:]
        for p in all {
            let key = crossSignature(for: p)
            buckets[key, default: []].append(p)
        }

        var out: [UnifiedPost] = []
        for (_, group) in buckets {
            // Sort by time and create clusters within the window
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
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
                    if abs(post.createdAt.timeIntervalSince(a.createdAt)) <= crossPostWindow {
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
        let pick: UnifiedPost = {
            switch preference {
            case .blueskyFirst:
                return cluster.first(where: { if case .bluesky = $0.network { return true } else { return false } })
                    ?? cluster.max(by: { $0.createdAt < $1.createdAt })!
            case .mastodonFirst:
                return cluster.first(where: { if case .mastodon = $0.network { return true } else { return false } })
                    ?? cluster.max(by: { $0.createdAt < $1.createdAt })!
            case .newest:
                return cluster.max(by: { $0.createdAt < $1.createdAt })!
            case .oldest:
                return cluster.min(by: { $0.createdAt < $1.createdAt })!
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
        let author = normalizeAuthor(p)
        let body   = normalizeBody(p.text)
        let mediaCount = p.media.count // robust across services (ignores differing CDN filenames)
        return "\(author)|\(body)|n\(mediaCount)"
    }

    private func normalizeAuthor(_ p: UnifiedPost) -> String {
        let base = (p.authorDisplayName?.isEmpty == false ? p.authorDisplayName! : p.authorHandle)
        return base
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }

    private func normalizeBody(_ a: AttributedString) -> String {
        var s = String(a.characters).lowercased()
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
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
    func ensureContains(postID: String, maxPages: Int = 6) async {
        // If already present in either cache, nothing to do
        if hasPost(id: postID) { return }
        var pages = 0
        while pages < maxPages {
            await loadMore()
            if hasPost(id: postID) { return }
            // If both cursors are exhausted, stop
            if mastodonCursor == nil && blueskyCursor == nil { break }
            pages += 1
        }
    }

    private func hasPost(id: String) -> Bool {
        if mastodonPosts.contains(where: { $0.id == id }) { return true }
        if blueskyPosts.contains(where: { $0.id == id }) { return true }
        if posts.contains(where: { $0.id == id }) { return true }
        return false
    }
}
