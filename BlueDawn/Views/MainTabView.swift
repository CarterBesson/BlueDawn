import SwiftUI

struct MainTabView: View {
    @State private var filter: TimelineFilter = .all
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            HomeTimelineView(filter: $filter)
                .overlay(alignment: .bottomLeading) { filterFAB() }
                .overlay(alignment: .bottomTrailing) { searchFAB() }
        }
        .sheet(isPresented: $showSearch) { SearchView() }
    }
}

private extension MainTabView {
    @ViewBuilder
    func filterFAB() -> some View {
        Menu {
            Button(action: { filter = .all }) {
                Label("Combined", systemImage: filter == .all ? "checkmark" : "rectangle.3.group")
            }
            Button(action: { filter = .bluesky }) {
                Label("Bluesky only", systemImage: filter == .bluesky ? "checkmark" : "cloud")
            }
            Button(action: { filter = .mastodon }) {
                Label("Mastodon only", systemImage: filter == .mastodon ? "checkmark" : "dot.radiowaves.left.and.right")
            }
        } label: {
            Image(systemName: iconForFilter(filter))
                .font(.system(size: 18, weight: .bold))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .menuStyle(.automatic)
        .padding(.leading, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("Timeline filter")
    }

    func iconForFilter(_ f: TimelineFilter) -> String {
        switch f {
        case .all: return "rectangle.3.group"
        case .bluesky: return "cloud"
        case .mastodon: return "dot.radiowaves.left.and.right"
        }
    }

    @ViewBuilder
    func searchFAB() -> some View {
        Button {
            showSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("Search")
    }
}
