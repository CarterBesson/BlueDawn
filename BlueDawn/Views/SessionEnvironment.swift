import SwiftUI

private struct SessionKey: EnvironmentKey {
    @MainActor
    static let defaultValue: SessionStore = SessionStore()
}

extension EnvironmentValues {
    var session: SessionStore {
        get { self[SessionKey.self] }
        set { self[SessionKey.self] = newValue }
    }
}

extension View {
    func sessionEnvironment(_ session: SessionStore) -> some View {
        environment(\.session, session)
    }
}
