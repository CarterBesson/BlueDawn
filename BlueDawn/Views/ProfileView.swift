import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State var viewModel: ProfileViewModel

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
                NavigationLink {
                    PostDetailView(post: post, viewModel: ThreadViewModel(session: session, root: post))
                } label: {
                    PostRow(post: post)
                }
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
        .navigationTitle("Profile")
        .task { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") { viewModel.error = nil }
        } message: { Text(viewModel.error ?? "") }
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
