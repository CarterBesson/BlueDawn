import SwiftUI

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel: TimelineViewModel? = nil
    @State private var showFilterMenu = false
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    HomeTimelineView(viewModel: vm)
                        .overlay(alignment: .bottomLeading) { filterFAB(vm) }
                        .overlay(alignment: .bottomTrailing) { searchFAB() }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { if viewModel == nil { viewModel = TimelineViewModel(session: session) } }
        .sheet(isPresented: $showSearch) { SearchView() }
    }
}

private extension MainTabView {
    @ViewBuilder
    func filterFAB(_ vm: TimelineViewModel) -> some View {
        Menu {
            Button(action: { vm.filter = .all }) {
                Label("Combined", systemImage: vm.filter == .all ? "checkmark" : "rectangle.3.group")
            }
            Button(action: { vm.filter = .bluesky }) {
                Label("Bluesky only", systemImage: vm.filter == .bluesky ? "checkmark" : "cloud")
            }
            Button(action: { vm.filter = .mastodon }) {
                Label("Mastodon only", systemImage: vm.filter == .mastodon ? "checkmark" : "dot.radiowaves.left.and.right")
            }
        } label: {
            Image(systemName: iconForFilter(vm.filter))
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

    func iconForFilter(_ f: TimelineViewModel.Filter) -> String {
        switch f {
        case .all: return "rectangle.3.group"
        case .bluesky: return "cloud"
        case .mastodon: return "dot.radiowaves.left.and.right"
        }
    }

    func labelForFilter(_ f: TimelineViewModel.Filter) -> String {
        switch f {
        case .all: return "Combined"
        case .bluesky: return "Bluesky"
        case .mastodon: return "Mastodon"
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
