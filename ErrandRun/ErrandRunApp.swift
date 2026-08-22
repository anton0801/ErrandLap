//
//  ErrandRunApp.swift
//  ErrandRun
//

import SwiftUI

@main
struct ErrandRunApp: App {
    @State private var store: AppStore
    @State private var auth: AuthStore
    @State private var sync: SyncEngine

    init() {
        let store = AppStore()
        let auth = AuthStore(store: store)
        let sync = SyncEngine(store: store)

        _store = State(initialValue: store)
        _auth = State(initialValue: auth)
        _sync = State(initialValue: sync)

        sync.attach()
        auth.onSignedIn = { [weak sync] _ in
            sync?.enable()
            Task { await sync?.syncNow(fullPull: true) }
        }
        auth.onSignedOut = { [weak sync] in
            sync?.disable()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(auth)
                .environment(sync)
                .tint(ER.scarlet)
                .task {
                    // A session restored from the Keychain starts syncing straight away.
                    // In local mode there is nothing to restore and nothing to enable.
                    guard AppMode.isConnected else { return }
                    if await APIClient.shared.currentSession() != nil {
                        sync.enable()
                    }
                }
        }
    }
}
