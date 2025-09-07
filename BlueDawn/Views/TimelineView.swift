import SwiftUI

struct TimelineView: View {
    @State var viewModel: TimelineViewModel
    @Environment(SessionStore.self) private var session
    @State private var showingError: Bool = false
    @State private var profileRoute: (Network, String)? = nil

    init(viewModel: TimelineViewModel) { _viewModel = State(initialValue: viewModel) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(viewModel.posts, id: \.id) { post in
                        HStack(alignment: .top, spacing: 12) {
                            // Avatar → Profile
                            Button {
                                profileRoute = (post.network, post.authorHandle)
                            } label: {
                                AvatarCircle(handle: post.authorHandle, url: post.authorAvatarURL)
                            }
                            .buttonStyle(.plain)

                            // Rest of the row → Post detail
                            NavigationLink {
                                PostDetailView(post: post, viewModel: ThreadViewModel(session: session, root: post))
                            } label: {
                                // IMPORTANT: hide the avatar in the row's content to avoid duplicating it
                                PostRow(post: post, showAvatar: false)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .onAppear {
                            if let idx = viewModel.posts.firstIndex(where: { $0.id == post.id }) {
                                viewModel.onItemAppear(index: idx)
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 12)
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.automatic)
                .refreshable { await viewModel.refresh() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.refresh() }
            .task(id: session.isBlueskySignedIn) { await viewModel.refresh() }
            .task(id: session.isMastodonSignedIn) { await viewModel.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .navigationDestination(isPresented: Binding(get: { profileRoute != nil }, set: { if !$0 { profileRoute = nil } })) {
                if let route = profileRoute {
                    ProfileView(network: route.0, handle: route.1, session: session)
                }
            }
            .overlay(alignment: .center) {
                if viewModel.isLoading && viewModel.posts.isEmpty { ProgressView("Loading...") }
            }
            .onChange(of: viewModel.error) { oldValue, newValue in
                showingError = (newValue != nil)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
        }
    }
}

private struct AvatarCircle: View {
    let handle: String
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Circle().fill(Color.secondary.opacity(0.2))
                    @unknown default: Circle().fill(Color.secondary.opacity(0.2))
                    }
                }
            } else {
                Circle().fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Text(String(handle.prefix(1).uppercased()))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
}
