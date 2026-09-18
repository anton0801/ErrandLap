//
//  AppTarget.swift
//  ErrandRun
//
//  ┌──────────────────────────────────────────────────────────────────────────┐
//  │  THE SWITCH THAT COMES FROM THE SERVER.                                  │
//  │                                                                          │
//  │  The server keeps one row in the `onAnalytics` table with one column,    │
//  │  `isOn`, and puts its value on EVERY response as a header:               │
//  │                                                                          │
//  │      X-App-Target: true          X-App-Target: false                     │
//  │                                                                          │
//  │  This object holds that value for the rest of the app. It is filled in   │
//  │  by the first request the app makes on launch, and refreshed by every    │
//  │  request after that, so it is never more than one call out of date.      │
//  │                                                                          │
//  │  WHERE TO PUT YOUR OWN LOGIC: `onChange` at the bottom of this file, or  │
//  │  read `AppTarget.shared.isOn` from anywhere. Both are marked below.      │
//  └──────────────────────────────────────────────────────────────────────────┘
//

import Foundation

@MainActor
final class AppTarget: ObservableObject {
    static let shared = AppTarget()

    /// nil until the server has answered once on this device. After that it is
    /// remembered between launches, so the value is available immediately —
    /// including before the network answers, and while offline.
    @Published private(set) var isOn: Bool?

    /// When the value last came from the server.
    @Published private(set) var checkedAt: Date?

    /// True once the server has answered at least once, ever, on this device.
    var isKnown: Bool { isOn != nil }

    /// Convenience for a call site that has to decide before the first answer
    /// arrives: unknown counts as off.
    var isOnOrOff: Bool { isOn ?? false }

    private let store = UserDefaults.standard
    private static let valueKey = "ERAppTargetValue"
    private static let checkedKey = "ERAppTargetCheckedAt"

    private init() {
        if store.object(forKey: Self.valueKey) != nil {
            isOn = store.bool(forKey: Self.valueKey)
        }
        if let stamp = store.object(forKey: Self.checkedKey) as? Date {
            checkedAt = stamp
        }
    }

    // MARK: Wiring

    /// Called once at launch. Subscribes to every future response, then makes the
    /// first request itself so the value arrives whether or not anyone is signed in.
    func start() async {
        guard AppMode.isConnected else { return }

        await APIClient.shared.setAppTargetHandler { value in
            Task { @MainActor in AppTarget.shared.apply(value) }
        }

        await refresh()
    }

    /// Asks the server directly. `/v1/health` needs no account, so this works on
    /// the sign-in screen as well as inside the app.
    ///
    /// Deterministic on purpose: when this returns, `isOn` already holds whatever
    /// the server just said, so launch code can await it and then read the value.
    @discardableResult
    func refresh() async -> Bool? {
        guard AppMode.isConnected else { return nil }

        // The body does not matter; the value rides on the response header, and
        // any answer at all — including an error — carries it.
        _ = try? await APIClient.shared.send("GET", "/v1/health", authorized: false)

        if let value = await APIClient.shared.latestAppTarget() {
            apply(value)
            return value
        }
        return isOn
    }

    // MARK: The value

    private func apply(_ value: Bool) {
        let changed = isOn != value

        isOn = value
        checkedAt = Date()
        store.set(value, forKey: Self.valueKey)
        store.set(checkedAt, forKey: Self.checkedKey)

        if changed {
            onChange(value)
        }
    }

    // ┌──────────────────────────────────────────────────────────────────────┐
    // │  YOUR LOGIC GOES HERE.                                               │
    // │                                                                      │
    // │  Called on the main actor whenever the value actually changes —      │
    // │  including the first time it arrives. Not called when the server     │
    // │  repeats a value the app already had.                                │
    // └──────────────────────────────────────────────────────────────────────┘
    private func onChange(_ value: Bool) {
        // Example of what can go here:
        //
        //     if value {
        //         // switch something on
        //     } else {
        //         // switch it off
        //     }
        //
        // Anywhere else in the app, read it directly:
        //
        //     if AppTarget.shared.isOn == true { … }
        //
        // or in a SwiftUI view, which will redraw when it changes:
        //
        //     @ObservedObject private var target = AppTarget.shared
        //     if target.isOnOrOff { … }

        #if DEBUG
        print("[AppTarget] x-app-target changed to \(value)")
        #endif
    }
}
