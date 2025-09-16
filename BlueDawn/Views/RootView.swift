import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            if session.isBlueskySignedIn || session.isMastodonSignedIn {
                HomeTimelineView(viewModel: TimelineViewModel(session: session))
            } else {
                LoginView()
            }
        }
    }
}
