import SwiftUI

struct AvatarCircle: View {
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
