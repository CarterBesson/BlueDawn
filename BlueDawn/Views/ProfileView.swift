import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    let network: Network
    let handle: String

    @State private var user: UnifiedUser? = nil
    @State private var posts: [UnifiedPost] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var error: String? = nil
    @State private var nextCursor: String? = nil

    // For opening booster/reposter profiles from the banner
    @State private var profileTarget: ProfileTarget? = nil
    @State private var pushProfile: Bool = false
    @State private var postSelection: UnifiedPost? = nil
    @State private var imageViewer: ImageViewerState? = nil
    @State private var isFollowing: Bool = false
    @State private var isTogglingFollow: Bool = false
    @State private var safariURL: URL? = nil
    @State private var toastText: String? = nil
    private struct ProfileTarget: Identifiable { let id = UUID(); let network: Network; let handle: String }

    var body: some View {
        List {
            if let u = user {
                header(user: u)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            ForEach(posts, id: \.id) { post in
                // Programmatic navigation to avoid conflicts with image taps
                PostRow(
                    post: post,
                    onOpenProfile: { network, handle in
                        profileTarget = ProfileTarget(network: network, handle: handle)
                        pushProfile = true
                    },
                    onOpenPost: { opened in
                        postSelection = opened
                    },
                    onTapImage: { tappedPost, idx in
                        imageViewer = ImageViewerState(post: tappedPost, index: idx)
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { postSelection = post }
                .listRowSeparator(.hidden)
                .onAppear {
                    if let idx = posts.firstIndex(where: { $0.id == post.id }),
                       idx >= posts.count - 5 {
                        Task { await loadMore() }
                    }
                }
            }

            if isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        // Handle tappable mentions inside bios or post text
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "bluesky" && url.host == "profile" {
                let comps = url.pathComponents.filter { $0 != "/" }
                if let handle = comps.first { profileTarget = ProfileTarget(network: .bluesky, handle: handle); pushProfile = true; return .handled }
            }
            if let scheme = url.scheme, (scheme == "http" || scheme == "https"), let host = url.host {
                let path = url.path
                if let statusID = extractMastoStatusID(fromPath: path) {
                    Task { await openMastodonStatus(host: host, id: statusID, url: url) }
                    return .handled
                }
                if path.hasPrefix("/@") {
                    let username = String(path.dropFirst(2))
                    profileTarget = ProfileTarget(network: .mastodon(instance: host), handle: username); pushProfile = true
                    return .handled
                }
                if path.hasPrefix("/users/") {
                    let comps = path.split(separator: "/").map(String.init)
                    if comps.count >= 2 {
                        profileTarget = ProfileTarget(network: .mastodon(instance: host), handle: comps[1]); pushProfile = true
                        return .handled
                    }
                }
                if let statusID = extractMastoStatusID(fromPath: path) {
                    Task { await openMastodonStatus(host: host, id: statusID, url: url) }
                    return .handled
                }
                if host == "bsky.app" && path.hasPrefix("/profile/") {
                    let handle = String(path.dropFirst("/profile/".count))
                    profileTarget = ProfileTarget(network: .bluesky, handle: handle); pushProfile = true
                    return .handled
                }
                // Non-profile web links
                if session.openLinksInApp {
                    #if canImport(SafariServices) && canImport(UIKit)
                    safariURL = url
                    return .handled
                    #else
                    return .systemAction
                    #endif
                }
            }
            return .systemAction
        })
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            if let u = user, let f = u.isFollowing { isFollowing = f }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .navigationDestination(item: $postSelection) {
            PostDetailView(post: $0)
        }
        .navigationDestination(isPresented: $pushProfile) {
            Group {
                if let target = profileTarget {
                    ProfileView(network: target.network, handle: target.handle)
                } else {
                    EmptyView()
                }
            }
        }
        .fullScreenCover(item: $imageViewer) { (selection: ImageViewerState) in
            ImageViewer(post: selection.post, startIndex: selection.index)
        }
        #if canImport(SafariServices)
        .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
            if let url = safariURL { SafariView(url: url) }
        }
        #endif
        .overlay(alignment: .bottom) {
            if let t = toastText {
                Text(t)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func extractMastoStatusID(fromPath path: String) -> String? {
        let comps = path.split(separator: "/").map(String.init)
        if comps.count >= 2, comps[0].hasPrefix("@") {
            let last = comps.last!
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: last)) { return last }
        }
        if let idx = comps.firstIndex(of: "statuses"), idx + 1 < comps.count {
            let cand = comps[idx + 1]
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cand)) { return cand }
        }
        return nil
    }

    @MainActor
    private func openMastodonStatus(host: String, id: String, url: URL) async {
        let client: MastodonClient
        if let c = session.mastodonClient, c.baseURL.host == host { client = c }
        else if let base = URL(string: "https://\(host)") { client = MastodonClient(baseURL: base, accessToken: "") }
        else { return }
        if let post = try? await client.fetchStatus(id: id) {
            postSelection = post
            return
        }
        // Fallback to SafariView if enabled
        #if canImport(SafariServices) && canImport(UIKit)
        if session.openLinksInApp { safariURL = url }
        #endif
    }

    @ViewBuilder
    private func header(user u: UnifiedUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let url = u.avatarURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Circle().fill(Color.secondary.opacity(0.2))
                            @unknown default: Circle().fill(Color.secondary.opacity(0.2))
                            }
                        }
                    } else {
                        Circle().fill(Color.secondary.opacity(0.2))
                    }
                }
                .frame(width: 72, height: 72).clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(u.displayName ?? u.handle).font(.title2.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: u.network == .bluesky ? "cloud" : "dot.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                        Text("@\(u.handle)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if hasKnownFollowState(u) && canFollow(u) && !isViewingSelf(u) {
                    Button {
                        Task { await handleToggleFollow(u) }
                    } label: {
                        HStack(spacing: 6) {
                            if isTogglingFollow {
                                ProgressView().controlSize(.small)
                            }
                            Text(isFollowing ? "Following" : "Follow")
                        }
                    }
                    .disabled(isTogglingFollow)
                    .applyFollowButtonStyle(isFollowing: isFollowing)
                    .controlSize(.regular)
                    .accessibilityLabel(isFollowing ? "Following \(u.displayName ?? u.handle)" : "Follow \(u.displayName ?? u.handle)")
                }
            }

            if let bio = u.bio, !bio.characters.isEmpty {
                Text(bio).font(.body)
            }

            HStack(spacing: 16) {
                if let c = u.postsCount { Label("\(c)", systemImage: "text.justify") }
                if let c = u.followersCount { Label("\(c)", systemImage: "person.2") }
                if let c = u.followingCount { Label("\(c)", systemImage: "arrow.forward") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }
}

private extension View {
    @ViewBuilder
    func applyFollowButtonStyle(isFollowing: Bool) -> some View {
        // Prefer newer bordered styles when available, else fall back safely.
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            if isFollowing {
                self.buttonStyle(BorderedButtonStyle())
            } else {
                self.buttonStyle(BorderedProminentButtonStyle())
            }
        } else {
            self.buttonStyle(DefaultButtonStyle())
        }
        #else
        self.buttonStyle(DefaultButtonStyle())
        #endif
    }
}

extension ProfileView {
    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let client = client()
            self.user = try await client.fetchUserProfile(handle: handle)
            let (p, cursor) = try await client.fetchAuthorFeed(handle: handle, cursor: nil)
            self.posts = p
            self.nextCursor = cursor
        } catch { self.error = error.localizedDescription }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        error = nil
        defer { isLoadingMore = false }
        do {
            let (more, next) = try await client().fetchAuthorFeed(handle: handle, cursor: cursor)
            // de-dupe by id
            var seen = Set(posts.map { $0.id })
            let unique = more.filter { seen.insert($0.id).inserted }
            self.posts.append(contentsOf: unique)
            self.nextCursor = next
        } catch { self.error = error.localizedDescription }
    }

    private func client() -> SocialClient {
        switch network {
        case .bluesky:
            precondition(session.blueskyClient != nil, "Not signed into Bluesky")
            return session.blueskyClient!
        case .mastodon(let instance):
            if let c = session.mastodonClient, c.baseURL.host == instance {
                return c
            }
            // Fallback public client for cross-instance profiles (no auth)
            let url = URL(string: "https://\(instance)")!
            return MastodonClient(baseURL: url, accessToken: "")
        }
    }

    @MainActor
    private func handleToggleFollow(_ u: UnifiedUser) async {
        guard !isTogglingFollow else { return }
        guard canFollow(u) else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let currentlyFollowing = isFollowing
        // Optimistic update
        withAnimation { isFollowing.toggle() }
        do {
            switch u.network {
            case .bluesky:
                guard let client = await session.blueskyClientEnsuringFreshToken() else { throw URLError(.userAuthenticationRequired) }
                if currentlyFollowing {
                    if let rkey = user?.bskyFollowRkey { try await client.unfollowUser(rkey: rkey) }
                    user?.isFollowing = false
                    user?.bskyFollowRkey = nil
                    showToast("Unfollowed @\(u.handle)")
                    Haptics.selection()
                } else {
                    // Extract DID from UnifiedUser.id ("bsky:<did>")
                    let did = u.id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                    let rkey = try await client.followUser(did: did)
                    user?.isFollowing = true
                    user?.bskyFollowRkey = rkey
                    showToast("Followed @\(u.handle)")
                    Haptics.selection()
                }
            case .mastodon(let instance):
                // Only allow follow if authed client matches this instance
                if let client = session.mastodonClient, client.baseURL.host == instance {
                    // Extract account ID from UnifiedUser.id ("mastodon:<id>")
                    let id = u.id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                    if currentlyFollowing {
                        try await client.unfollowUser(id: id); user?.isFollowing = false
                        showToast("Unfollowed @\(u.handle)"); Haptics.selection()
                    } else {
                        try await client.followUser(id: id); user?.isFollowing = true
                        showToast("Followed @\(u.handle)"); Haptics.selection()
                    }
                } else {
                    throw URLError(.userAuthenticationRequired)
                }
            }
        } catch {
            // Revert on failure
            withAnimation { isFollowing = currentlyFollowing }
            self.error = error.localizedDescription
            Haptics.selection()
        }
    }

    private func hasKnownFollowState(_ u: UnifiedUser) -> Bool { u.isFollowing != nil }

    private func showToast(_ text: String) {
        withAnimation { toastText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { toastText = nil }
        }
    }

    private func canFollow(_ u: UnifiedUser) -> Bool {
        switch u.network {
        case .bluesky:
            return session.isBlueskySignedIn && (session.blueskyClient != nil)
        case .mastodon(let instance):
            if let c = session.mastodonClient, session.isMastodonSignedIn {
                return c.baseURL.host == instance
            }
            return false
        }
    }

    private func isViewingSelf(_ u: UnifiedUser) -> Bool {
        switch u.network {
        case .bluesky:
            if let did = session.blueskyDid {
                // u.id is like "bsky:<did>"
                if let userDid = u.id.split(separator: ":", maxSplits: 1).last, userDid == Substring(did) { return true }
            }
            if let myHandle = session.signedInHandleBluesky, myHandle == u.handle { return true }
            return false
        case .mastodon(let instance):
            // Hide if we know our own handle and instance matches
            if let myHandle = session.signedInHandleMastodon,
               let c = session.mastodonClient, c.baseURL.host == instance {
                return myHandle == u.handle || "@\(myHandle)" == u.handle
            }
            return false
        }
    }
}
