import SwiftUI

struct TimelineRow: View {
    let post: UnifiedPost
    let session: SessionStore
    let onOpenPost: (UnifiedPost) -> Void
    let onOpenProfile: (Network, String) -> Void
    let onTapImage: (UnifiedPost, Int) -> Void
    let onOpenExternalURL: (URL) -> Void

    var body: some View {
        Group {
            if let threadPreview = post.threadPreview {
                // Show thread preview
                ThreadPreviewView(
                    rootPost: post,
                    preview: threadPreview,
                    session: session,
                    onOpenProfile: onOpenProfile,
                    onOpenPost: onOpenPost,
                    onTapImage: onTapImage,
                    onOpenExternalURL: onOpenExternalURL
                )
            } else {
                // Show regular post; use programmatic navigation to avoid nested link issues
                HStack(alignment: .top, spacing: 12) {
                    Button { onOpenProfile(post.network, post.authorHandle) } label: {
                        AvatarCircle(handle: post.authorHandle, url: post.authorAvatarURL)
                    }
                    .buttonStyle(.plain)

                    PostRow(
                        post: post,
                        showAvatar: false,
                        onOpenProfile: onOpenProfile,
                        onTapImage: { tappedPost, idx in onTapImage(tappedPost, idx) },
                        onOpenExternalURL: onOpenExternalURL
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenPost(post) }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }
}
