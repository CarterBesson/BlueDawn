import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search…", text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
                .padding()

                Spacer()
                if query.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("Type to search across networks").foregroundStyle(.secondary)
                    }
                } else {
                    Text("Results for \(query)")
                        .foregroundStyle(.secondary)
                        .padding()
                }
                Spacer()
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

