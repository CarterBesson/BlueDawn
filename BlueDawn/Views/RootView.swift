import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isBlueskySignedIn || session.isMastodonSignedIn {
            MainTabView()
        } else {
            NavigationStack {
                LoginView()
            }
        }
    }
}
