import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        // Single-screen shell — Timeline is the root. No TabView.
        TimelineView(viewModel: TimelineViewModel(session: session))
    }
}
