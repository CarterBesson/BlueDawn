import SwiftUI

// Thin wrapper screen that owns a TimelineViewModel and embeds TimelineList
struct HomeTimelineView: View {
    @Environment(SessionStore.self) private var session

    // Use @State because TimelineViewModel is built with the Observation framework (@Observable)
    @State private var viewModel: TimelineViewModel

    // Custom init to seed the @State from the parent
    init(viewModel: TimelineViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    // Minimal state required by TimelineList
    @State private var anchorID: String? = nil
    @State private var pendingScrollToID: String? = nil
    @State private var jumpInProgress = false
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
              let idx = viewModel.posts.firstIndex(where: { $0.id == anchorID }) else { return 0 }
        return idx // number of items before the anchor
    }

    var body: some View {
        TimelineList(
            posts: viewModel.posts,
            isLoadingMore: viewModel.isLoadingMore,
            session: session,
            onItemAppear: { viewModel.onItemAppear(index: $0) },
            onOpenPost: { post in
                postSelection = post
            },
            anchorID: $anchorID,
            pendingScrollToID: $pendingScrollToID,
            jumpInProgress: $jumpInProgress,
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
                await viewModel.refresh()
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
            if !didInitialRestore || jumpInProgress || viewModel.isLoading { return }
            guard let new, new != old else { return }
            viewModel.updateAnchorPostID(new)
        }
        #endif
        .navigationDestination(item: $postSelection) { post in
            PostDetailView(post: post, viewModel: ThreadViewModel(session: session, root: post))
        }
        .navigationDestination(item: $profileRoute) { route in
            ProfileView(network: route.network, handle: route.handle, session: session)
        }
        .overlay(alignment: .topTrailing) {
            if aboveCount > 0 {
                Button {
                    if let topID = viewModel.posts.first?.id {
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
            let restoredAnchor = await viewModel.loadPersisted()
            if let anchor = restoredAnchor {
                // Apply anchor immediately and schedule an explicit jump once rows exist
                anchorID = anchor
                DispatchQueue.main.async { pendingScrollToID = anchor }
            }
            // Fetch new items (if any) without disturbing position
            await viewModel.refresh()
            // Reassert anchor after refresh to avoid drift
            if let anchor = restoredAnchor { anchorID = anchor }
            // Mark restore complete after any jump animation settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { didInitialRestore = true }
        }
        .onChange(of: viewModel.filter) { _, _ in
            // When switching filters, jump to top of the new dataset
            if let topID = viewModel.posts.first?.id {
                anchorID = topID
                pendingScrollToID = topID
            }
        }
        .onChange(of: viewModel.error) { _, new in
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
    let onOpenProfile: (Network, String) -> Void
    let onTapImage: (UnifiedPost, Int) -> Void
    let onOpenExternalURL: (URL) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
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
            .refreshable { await onRefresh() }
            .scrollPosition(id: $anchorID, anchor: .top)
            .transaction { if !jumpInProgress { $0.animation = nil } }
            .onChange(of: pendingScrollToID) { _, new in
                guard let id = new else { return }
                jumpInProgress = true
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { jumpInProgress = false }
                pendingScrollToID = nil
            }
        }
    }
}
