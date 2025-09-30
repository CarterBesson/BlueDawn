import SwiftUI

struct QuotedPostCard: View {
    let post: QuotedPost
    var onOpenPost: ((UnifiedPost) -> Void)? = nil
    var onOpenProfile: ((Network, String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    onOpenProfile?(post.network, post.authorHandle)
                } label: {
                    AvatarCircle(handle: post.authorHandle, url: post.authorAvatarURL, size: 22)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(post.authorDisplayName?.isEmpty == false ? post.authorDisplayName! : post.authorHandle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("@\(post.authorHandle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }

                    Text(post.text)
                        .font(.subheadline)
                        .lineLimit(6)
                        .foregroundStyle(.primary)
                }
            }

            if !post.media.isEmpty {
                // Show up to 2 thumbnails for compactness
                let thumbs = Array(post.media.prefix(2))
                HStack(spacing: 6) {
                    ForEach(Array(thumbs.enumerated()), id: \.offset) { _, m in
                        ZStack {
                            switch m.kind {
                            case .image:
                                AsyncImage(url: m.url) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle().fill(Color.secondary.opacity(0.1)).overlay(ProgressView())
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        Rectangle().fill(Color.secondary.opacity(0.15)).overlay(Image(systemName: "photo").font(.caption))
                                    @unknown default:
                                        Rectangle().fill(Color.secondary.opacity(0.15))
                                    }
                                }
                            case .video, .gif:
                                Rectangle().fill(Color.secondary.opacity(0.12))
                                    .overlay(Image(systemName: "play.fill").font(.caption).foregroundStyle(.white))
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpenPost?(toUnified(post)) }
        .accessibilityLabel("Quoted post by \(post.authorDisplayName ?? post.authorHandle)")
    }

    private func toUnified(_ q: QuotedPost) -> UnifiedPost {
        UnifiedPost(
            id: q.id,
            network: q.network,
            authorHandle: q.authorHandle,
            authorDisplayName: q.authorDisplayName,
            authorAvatarURL: q.authorAvatarURL,
            createdAt: q.createdAt,
            text: q.text,
            media: q.media,
            cwOrLabels: nil,
            counts: PostCounts(replies: nil, boostsReposts: nil, favLikes: nil),
            inReplyToID: nil,
            isRepostOrBoost: false,
            bskyCID: nil,
            bskyLikeRkey: nil,
            bskyRepostRkey: nil,
            isLiked: false,
            isReposted: false,
            isBookmarked: false,
            boostedByHandle: nil,
            boostedByDisplayName: nil,
            crossPostAlternates: nil,
            isCrossPostCanonical: false,
            threadPreview: nil,
            quotedPost: nil,
            externalURL: nil
        )
    }
}
