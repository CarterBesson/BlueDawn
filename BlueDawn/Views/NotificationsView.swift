import SwiftUI

struct NotificationsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Notifications")
                .font(.title2).bold()
            Text("Coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Notifications")
    }
}

