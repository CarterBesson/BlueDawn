import SwiftUI

struct MyProfilesView: View {
    @Environment(SessionStore.self) private var session
    
    private enum Selection: String, CaseIterable, Identifiable {
        case bluesky
        case mastodon
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .bluesky: return "cloud"
            case .mastodon: return "dot.radiowaves.left.and.right"
            }
        }
    }

    @State private var selection: Selection = .bluesky

    private var available: [Selection] {
        var out: [Selection] = []
        if session.isBlueskySignedIn { out.append(.bluesky) }
        if session.isMastodonSignedIn { out.append(.mastodon) }
        return out
    }

    var body: some View {
        VStack(spacing: 12) {
            if available.isEmpty {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Sign in to Bluesky or Mastodon to view your profile.")
                )
            } else {
                if available.count > 1 {
                    Picker("Network", selection: $selection) {
                        ForEach(available) { sel in
                            Label(sel.label, systemImage: sel.systemImage).tag(sel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                // Profile content
                switch selection {
                case .bluesky:
                    if let handle = session.signedInHandleBluesky {
                        ProfileView(network: .bluesky, handle: handle, session: session)
                    } else {
                        missingHandleView("Bluesky")
                    }
                case .mastodon:
                    if let handle = session.signedInHandleMastodon, let client = session.mastodonClient {
                        let base = client.baseURL.host ?? client.baseURL.absoluteString
                        ProfileView(network: .mastodon(instance: base), handle: handle, session: session)
                    } else {
                        missingHandleView("Mastodon")
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Initialize selection to a signed-in account
            if available.contains(.bluesky) { selection = .bluesky }
            else if available.contains(.mastodon) { selection = .mastodon }
        }
    }

    @ViewBuilder
    private func missingHandleView(_ networkName: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text("Couldn’t load your \(networkName) profile.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
