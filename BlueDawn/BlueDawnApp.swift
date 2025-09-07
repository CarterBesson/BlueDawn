//
//  BlueDawnApp.swift
//  BlueDawn
//
//  Created by Carter Besson on 9/3/25.
//

import SwiftUI
import Observation

@main
struct BlueDawnApp: App {
    @State private var session = SessionStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.restoreOnLaunch() }
        }
    }
}
