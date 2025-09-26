import SwiftUI

struct MainTabView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeTimelineView(viewModel: TimelineViewModel(session: session))
                        .navigationTitle("Home")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
            
            Tab("Notifications", systemImage: "bell") {
                NavigationStack {
                    NotificationsView()
                        .navigationTitle("Notifications")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
            Tab(role: .search) {
                NavigationStack {
                    // Replace with your actual search view when available
                    Text("Search")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle("Search")
                        .navigationBarTitleDisplayMode(.large)
                        .glassEffect(.regular.tint(.orange).interactive())
                }
            }
        }
    }
}
