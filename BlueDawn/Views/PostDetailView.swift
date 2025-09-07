import SwiftUI

struct PostDetailView: View {
    @Environment(SessionStore.self) private var session
    let post: UnifiedPost
    @State var viewModel: ThreadViewModel

    init(post: UnifiedPost, viewModel: ThreadViewModel) {
        self.post = post
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Ancestor context ABOVE the focused post
                if !viewModel.ancestors.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("In reply to")
                            .font(.headline)
                            .padding(.bottom, 8)

                        ForEach(viewModel.ancestors, id: \.id) { anc in
                            HStack(alignment: .top, spacing: 10) {
                                // Avatar → Profile
                                NavigationLink {
                                    ProfileView(network: anc.network, handle: anc.authorHandle, session: session)
                                } label: {
                                    Group {
                                        if let url = anc.authorAvatarURL {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .empty: Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                                                case .success(let image): image.resizable().scaledToFill()
                                                case .failure: Circle().fill(Color.secondary.opacity(0.2))
                                                @unknown default: Circle().fill(Color.secondary.opacity(0.2))
                                                }
                                            }
                                        } else { Circle().fill(Color.secondary.opacity(0.2)) }
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                                }
                                .buttonStyle(.plain)

                                // Content → Post detail
                                NavigationLink {
                                    PostDetailView(post: anc, viewModel: ThreadViewModel(session: session, root: anc))
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(anc.authorDisplayName?.isEmpty == false ? anc.authorDisplayName! : anc.authorHandle)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Text(anc.text)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    .padding(.bottom, 8)
                }

                header
                content
                if !post.media.isEmpty { mediaGrid }
                actionBar
                Divider().padding(.vertical, 6)
                repliesSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await viewModel.load() }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar → Profile (tappable)
            NavigationLink {
                ProfileView(network: post.network, handle: post.authorHandle, session: session)
            } label: {
                avatar
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("@\(post.authorHandle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: networkIconName)
                    .foregroundStyle(.secondary)
                Text(fullDate(post.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var avatar: some View {
        Group {
            if let url = post.authorAvatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle().fill(Color.secondary.opacity(0.2))
            .overlay(
                Text(String(post.authorHandle.prefix(1).uppercased()))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Content
    private var content: some View {
        Text(post.text)
            .font(.body)
            .textSelection(.enabled)
    }

    // MARK: - Media
    private var mediaGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(Array(post.media.enumerated()), id: \.offset) { _, m in
                AsyncImage(url: m.url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Color.secondary.opacity(0.1)).overlay(ProgressView())
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Rectangle().fill(Color.secondary.opacity(0.15)).overlay(Image(systemName: "photo"))
                    @unknown default:
                        Rectangle().fill(Color.secondary.opacity(0.15))
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
            }
        }
    }

    // MARK: - Replies
    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Replies")
                .font(.headline)
                .padding(.bottom, 8)

            if viewModel.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 12)
            }

            ForEach(viewModel.items) { item in
                HStack(alignment: .top, spacing: 10) {
                    // Avatar → Profile
                    NavigationLink {
                        ProfileView(network: item.post.network, handle: item.post.authorHandle, session: session)
                    } label: {
                        Group {
                            if let url = item.post.authorAvatarURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty: Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                                    case .success(let image): image.resizable().scaledToFill()
                                    case .failure: Circle().fill(Color.secondary.opacity(0.2))
                                    @unknown default: Circle().fill(Color.secondary.opacity(0.2))
                                    }
                                }
                            } else { Circle().fill(Color.secondary.opacity(0.2)) }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Content → Post detail
                    NavigationLink {
                        PostDetailView(post: item.post, viewModel: ThreadViewModel(session: session, root: item.post))
                    } label: {
                        PostRow(post: item.post, showAvatar: false)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(item.depth) * 16)
                .padding(.vertical, 4)

                Divider().padding(.leading, CGFloat(item.depth) * 16)
            }

            if let err = viewModel.error {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions
    private var actionBar: some View {
        HStack(spacing: 24) {
            Image(systemName: "bubble.left")
            Image(systemName: "arrow.2.squarepath")
            Image(systemName: "heart")
            Spacer()
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { share() } label: { Image(systemName: "square.and.arrow.up") }
        }
    }

    private func share() { /* TODO: add share link per-network */ }

    // MARK: - Helpers
    private var networkIconName: String {
        switch post.network {
        case .bluesky: return "cloud"
        case .mastodon(_): return "dot.radiowaves.left.and.right"
        }
    }

    private var displayName: String {
        post.authorDisplayName?.isEmpty == false ? post.authorDisplayName! : post.authorHandle
    }

    private func fullDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
