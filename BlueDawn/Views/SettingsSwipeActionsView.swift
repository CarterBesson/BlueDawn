import SwiftUI

struct SettingsSwipeActionsView: View {
    @Environment(SessionStore.self) private var session

    private var options: [SessionStore.SwipeAction] { SessionStore.SwipeAction.allCases }

    var body: some View {
        List {
            Section("Left Swipe (leading)") {
                pickerRow(title: "Short swipe", selection: Binding(get: { session.swipeLeadingShort }, set: { session.swipeLeadingShort = $0 }))
                pickerRow(title: "Long swipe", selection: Binding(get: { session.swipeLeadingLong }, set: { session.swipeLeadingLong = $0 }))
            }
            Section("Right Swipe (trailing)") {
                pickerRow(title: "Short swipe", selection: Binding(get: { session.swipeTrailingShort }, set: { session.swipeTrailingShort = $0 }))
                pickerRow(title: "Long swipe", selection: Binding(get: { session.swipeTrailingLong }, set: { session.swipeTrailingLong = $0 }))
            }
            Section(footer: Text("Full swipe triggers the 'Long swipe' action on that side. A partial swipe reveals both actions to tap.")) {
                EmptyView()
            }
        }
        .navigationTitle("Swipe Actions")
    }

    private func pickerRow(title: String, selection: Binding<SessionStore.SwipeAction>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options) { opt in
                    Label(opt.label, systemImage: opt.systemImage).tag(opt)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

