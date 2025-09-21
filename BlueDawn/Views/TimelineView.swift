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
    @State private var visibleIDs: Set<String> = []
    @State private var anchorID: String? = nil
    @State private var pendingScrollToID: String? = nil
    @State private var jumpInProgress = false
    @State private var imageViewer: ImageViewerState? = nil
    @State private var postSelection: UnifiedPost? = nil
    @State private var safariURL: URL? = nil

    private struct ProfileRoute: Identifiable, Hashable {
        let id = UUID()
        let network: Network
        let handle: String
    }
    @State private var profileRoute: ProfileRoute? = nil

    var body: some View {
        TimelineList(
            posts: viewModel.posts,
            isLoadingMore: viewModel.isLoadingMore,
            session: session,
            onItemAppear: { viewModel.onItemAppear(index: $0) },
            onOpenPost: { post in
                postSelection = post
            },
            visibleIDs: $visibleIDs,
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
            onRefresh: { await viewModel.refresh() },
            onUpdateAnchor: { items in
                // Choose first item in on-screen order whose id is visible
                if let firstVisible = items.first(where: { visibleIDs.contains($0.id) }) {
                    anchorID = firstVisible.id
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
        #endif
        .navigationDestination(item: $postSelection) { post in
            PostDetailView(post: post, viewModel: ThreadViewModel(session: session, root: post))
        }
        .navigationDestination(item: $profileRoute) { route in
            ProfileView(network: route.network, handle: route.handle, session: session)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                        .accessibilityLabel("Settings")
                }
            }
        }
        .task { await viewModel.refresh() }
    }
}


struct TimelineList: View {
    let posts: [UnifiedPost]
    let isLoadingMore: Bool
    let session: SessionStore
    let onItemAppear: (Int) -> Void
    let onOpenPost: (UnifiedPost) -> Void
    @Binding var visibleIDs: Set<String>
    @Binding var anchorID: String?
    @Binding var pendingScrollToID: String?
    @Binding var jumpInProgress: Bool
    let onOpenProfile: (Network, String) -> Void
    let onTapImage: (UnifiedPost, Int) -> Void
    let onOpenExternalURL: (URL) -> Void
    let onRefresh: () async -> Void
    let onUpdateAnchor: ([UnifiedPost]) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(posts) { post in
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
                        if let idx = posts.firstIndex(where: { $0.id == post.id }) { onItemAppear(idx) }
                        visibleIDs.insert(post.id)
                        onUpdateAnchor(posts)
                    }
                    .onDisappear {
                        visibleIDs.remove(post.id)
                        onUpdateAnchor(posts)
                    }
                }

                if isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 12)
                }
            }
            .listStyle(.plain)
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
