import SwiftUI

struct ThreadPreviewView: View {
    let rootPost: UnifiedPost
    let preview: ThreadPreview
    let session: SessionStore
    let onOpenProfile: (Network, String) -> Void
    let onOpenPost: (UnifiedPost) -> Void
    let onTapImage: (UnifiedPost, Int) -> Void
    let onOpenExternalURL: (URL) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Root post
            HStack(alignment: .top, spacing: 12) {
                Button { onOpenProfile(rootPost.network, rootPost.authorHandle) } label: {
                    AvatarCircle(handle: rootPost.authorHandle, url: rootPost.authorAvatarURL)
                }
                .buttonStyle(.plain)

                PostRow(
                    post: rootPost,
                    showAvatar: false,
                    onOpenProfile: onOpenProfile,
                    onTapImage: { tappedPost, idx in onTapImage(tappedPost, idx) },
                    onOpenExternalURL: onOpenExternalURL
                )
                .contentShape(Rectangle())
                .onTapGesture { onOpenPost(rootPost) }
            }
            .padding(.vertical, 8)
            
            if preview.totalReplyCount > 0 {
                // Thread continuation line and info
                HStack {
                    VStack {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2, height: 20)
                        Spacer()
                    }
                    .frame(width: 44) // Match avatar width
                    
                    HStack(spacing: 8) {
                        if preview.conversationParticipants.count > 2 {
                            Text("\(preview.conversationParticipants.count) people")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        Text("\(preview.totalReplyCount) replies")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .frame(height: 20)
                
                // Recent replies
                ForEach(preview.recentReplies) { reply in
                    HStack(alignment: .top, spacing: 12) {
                        Button { onOpenProfile(reply.network, reply.authorHandle) } label: {
                            AvatarCircle(handle: reply.authorHandle, url: reply.authorAvatarURL)
                        }
                        .buttonStyle(.plain)
                        
                        PostRow(
                            post: reply,
                            showAvatar: false,
                            onOpenProfile: onOpenProfile,
                            onTapImage: { tappedPost, idx in onTapImage(tappedPost, idx) },
                            onOpenExternalURL: onOpenExternalURL
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenPost(reply) }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
