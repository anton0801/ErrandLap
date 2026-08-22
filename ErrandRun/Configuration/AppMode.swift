//
//  AppMode.swift
//  ErrandRun
//
//  ┌──────────────────────────────────────────────────────────────────────────┐
//  │  ONE SWITCH: does this build talk to the server, or not?                 │
//  │                                                                          │
//  │  Right now it is `.localOnly`. Everything lives on the phone: no sign-in │
//  │  screen, no sync, no network calls at all. The app is complete this way  │
//  │  — it is what it was before the server existed.                          │
//  │                                                                          │
//  │  The whole client–server layer is still here and still compiles:         │
//  │  APIClient, AuthStore, SyncEngine, the auth and account screens, the     │
//  │  WebView portal. Nothing was removed, and nothing about it is guessed —  │
//  │  it has been tested against the live API.                                │
//  │                                                                          │
//  │  WHEN THE SERVER IS UP, THE WHOLE CHANGE IS:                             │
//  │                                                                          │
//  │      static let current: Mode = .connected                               │
//  │                                                                          │
//  │  and, if the address moved, the one line in APIConfiguration.baseURL.    │
//  │  That is it. See LOCAL-MODE.md next to the project for what flips.       │
//  └──────────────────────────────────────────────────────────────────────────┘
//

import Foundation

enum AppMode {
    enum Mode {
        /// Everything on the phone. No accounts, no network.
        case localOnly
        /// Accounts, sync and the WebView portal, against APIConfiguration.baseURL.
        case connected
    }

    // ⬇︎ THE SWITCH
    static let current: Mode = .localOnly

    /// A build can be pointed at the server without touching the source, which is
    /// handy for testing the connected path before shipping it:
    ///     xcrun simctl spawn booted defaults write <bundle-id> ERForceConnected -bool YES
    static var isConnected: Bool {
        if UserDefaults.standard.bool(forKey: "ERForceConnected") {
            return true
        }
        return current == .connected
    }

    static var isLocalOnly: Bool { !isConnected }
}

// MARK: - Wording that has to match reality

/// The app says out loud where the data goes. That sentence is different in each
/// mode, so it lives here rather than being written into a screen — flipping the
/// switch flips the words with it, and the app never claims something untrue.
extension AppMode {
    /// Onboarding, last page.
    static var onboardingStorageLine: String {
        isConnected
            ? "Your errands sync to your own account, so a new phone finds them. Nothing is shared with anyone else."
            : "Everything stays on this phone. No account, no sign-up, nothing sent anywhere."
    }

    /// Under the setup form.
    static var setupStorageLine: String {
        isConnected
            ? "This is stored in your account and on this phone. The map service is used for one thing only: the real travel time between two points."
            : "This stays on this phone. The map service is used for one thing only: the real travel time between two points."
    }

    /// Next to the address field of a place.
    static var addressHint: String {
        isConnected
            ? "Used once to work out travel time, and kept in your own account."
            : "Used once to work out travel time. Nothing is uploaded anywhere."
    }

    /// About screen.
    static var aboutStorageLine: String {
        isConnected
            ? "Your data lives on this phone and in your own account, and nowhere else."
            : "Everything is stored on this phone. No account, no sign-up."
    }
}
