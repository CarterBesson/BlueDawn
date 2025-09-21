import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State var viewModel: ProfileViewModel
    // For opening booster/reposter profiles from the banner
    @State private var profileTarget: ProfileTarget? = nil
    @State private var pushProfile: Bool = false
    @State private var postSelection: UnifiedPost? = nil
    @State private var imageViewer: ImageViewerState? = nil
    @State private var isFollowing: Bool = false
    @State private var safariURL: URL? = nil
    private struct ProfileTarget: Identifiable { let id = UUID(); let network: Network; let handle: String }

    init(network: Network, handle: String, session: SessionStore) {
        _viewModel = State(initialValue: ProfileViewModel(session: session, network: network, handle: handle))
    }

    var body: some View {
        List {
            if let u = viewModel.user {
                header(user: u)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            ForEach(viewModel.posts, id: \.id) { post in
                // Programmatic navigation to avoid conflicts with image taps
                PostRow(
                    post: post,
                    onOpenProfile: { network, handle in
                        profileTarget = ProfileTarget(network: network, handle: handle)
                        pushProfile = true
                    },
                    onTapImage: { tappedPost, idx in
                        imageViewer = ImageViewerState(post: tappedPost, index: idx)
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { postSelection = post }
                .listRowSeparator(.hidden)
                .onAppear {
                    if let idx = viewModel.posts.firstIndex(where: { $0.id == post.id }),
                       idx >= viewModel.posts.count - 5 {
                        Task { await viewModel.loadMore() }
                    }
                }
            }

            if viewModel.isLoadingMore {
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
                if path.hasPrefix("/@") {
                    let username = String(path.dropFirst(2))
                    let handle = "\(username)@\(host)"
                    profileTarget = ProfileTarget(network: .mastodon(instance: host), handle: handle); pushProfile = true
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
        .task { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") { viewModel.error = nil }
        } message: { Text(viewModel.error ?? "") }
        .navigationDestination(item: $postSelection) {
            PostDetailView(post: $0, viewModel: ThreadViewModel(session: session, root: $0))
        }
        .navigationDestination(isPresented: $pushProfile) {
            Group {
                if let target = profileTarget {
                    ProfileView(network: target.network, handle: target.handle, session: session)
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

                Button {
                    // UI-only toggle for now
                    isFollowing.toggle()
                } label: {
                    Text(isFollowing ? "Following" : "Follow")
                }
                .applyFollowButtonStyle(isFollowing: isFollowing)
                .controlSize(.regular)
                .accessibilityLabel(isFollowing ? "Following \(u.displayName ?? u.handle)" : "Follow \(u.displayName ?? u.handle)")
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
