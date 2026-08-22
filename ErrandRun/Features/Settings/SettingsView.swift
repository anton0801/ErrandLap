//
//  SettingsView.swift
//  ErrandRun
//

import SwiftUI
import UniformTypeIdentifiers

enum SettingsRoute: Hashable {
    case sparkRun
    case account
    case profile
    case windows
    case travelTimes
    case notifications
    case data
    case about
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var path: [SettingsRoute] = []

    /// The same row in both modes, so nothing moves when the server arrives.
    private var accountTitle: String {
        AppMode.isConnected ? "Account" : "Your Data"
    }

    private var accountDetail: String {
        guard AppMode.isConnected else {
            return "Kept on this phone. Sync arrives in an update."
        }
        let email = auth.email.isEmpty ? "Signed in" : auth.email
        switch sync.status {
        case .offline: return "\(email) · offline, changes are queued"
        case .syncing: return "\(email) · syncing"
        case .synced: return "\(email) · in step with the server"
        default: return email
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ERScreen(sparkSeed: 27) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ERNavBar(title: "Settings", onBack: { dismiss() })

                        ERNavRow(title: accountTitle, detail: accountDetail, index: 0) {
                            path.append(.account)
                        }
                        // The mini-app is served by the API, so it only exists when
                        // there is a server to serve it. See WebPortalView.swift.
                        if AppMode.isConnected {
                            ERNavRow(title: "Spark Run", detail: "A short seasonal run, in the app's colours.", index: 1) {
                                path.append(.sparkRun)
                            }
                        }
                        ERNavRow(title: "Profile", detail: "Name, home, work, walking pace.", index: 0) {
                            path.append(.profile)
                        }
                        ERNavRow(title: "Windows", detail: "\(store.data.windows.count) free window\(store.data.windows.count == 1 ? "" : "s").", index: 1) {
                            path.append(.windows)
                        }
                        ERNavRow(title: "Travel Times", detail: "Measured once, kept, recalculated by hand.", index: 2) {
                            path.append(.travelTimes)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Travel Mode")
                            ERChipRow(items: TravelMode.allCases,
                                      title: { $0.title },
                                      selection: Binding(
                                        get: { store.data.settings.travelMode },
                                        set: { newValue in store.mutate { $0.settings.travelMode = newValue } }
                                      ))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Buffer Between Stops")
                            ERChipRow(items: [0, 5, 10, 15],
                                      title: { "\($0) min" },
                                      selection: Binding(
                                        get: { store.data.settings.buffer },
                                        set: { newValue in store.mutate { $0.settings.buffer = newValue } }
                                      ))
                            ERNote(text: "Parking, finding the entrance, the lift. Added to every leg of every route.")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Learning")
                            ERCard {
                                ERToggleRow(title: "Use my measured times",
                                            subtitle: "After two visits the app plans with your own average instead of your estimate.",
                                            isOn: Binding(
                                                get: { store.data.settings.learnFromVisits },
                                                set: { newValue in store.mutate { $0.settings.learnFromVisits = newValue } }
                                            ))
                            }
                        }

                        ERNavRow(title: "Notifications", detail: store.data.settings.notificationsEnabled ? "On" : "Off", index: 3) {
                            path.append(.notifications)
                        }
                        ERNavRow(title: "Data", detail: "Export, import, clear, delete.", index: 4) {
                            path.append(.data)
                        }
                        ERNavRow(title: "About", detail: "What this app promises and what it does not.", index: 5) {
                            path.append(.about)
                        }

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: SettingsRoute.self) { route in
                Group {
                    switch route {
                    case .sparkRun: WebPortalView()
                    case .account:
                        if AppMode.isConnected {
                            AccountView()
                        } else {
                            SyncStatusView()
                        }
                    case .profile: SetupView(isInitial: false, onClose: { path.removeLast() })
                    case .windows: WindowsView()
                    case .travelTimes: TravelTimesView()
                    case .notifications: NotificationSettingsView()
                    case .data: DataSettingsView()
                    case .about: AboutView()
                    }
                }
                .navigationBarHidden(true)
            }
        }
    }
}

// MARK: - Notifications

struct NotificationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var denied = false

    var body: some View {
        ERScreen(sparkSeed: 28) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Notifications", onBack: { dismiss() })

                    ERNote(text: "Reminders are scheduled on this phone. Nothing about them is sent anywhere.")

                    ERCard {
                        ERToggleRow(title: "Reminders on",
                                    isOn: Binding(
                                        get: { store.data.settings.notificationsEnabled },
                                        set: { newValue in
                                            if newValue {
                                                Task {
                                                    let granted = await Notifications.shared.requestAuthorization()
                                                    store.mutate { $0.settings.notificationsEnabled = granted }
                                                    denied = !granted
                                                }
                                            } else {
                                                store.mutate { $0.settings.notificationsEnabled = false }
                                            }
                                        }
                                    ))
                    }

                    if denied {
                        ERErrorState(title: "Not Allowed",
                                     message: "Notifications are switched off for Errand Run in the system settings. Everything else in the app keeps working.")
                    }

                    if store.data.settings.notificationsEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "What to Remind About")
                            toggle("Window Starts Soon", \.windowStartsSoon)
                            toggle("Leave By", \.leaveBy)
                            toggle("Place Closing Today", \.placeClosingToday)
                            toggle("Deadline With Few Windows Left", \.deadlineFewWindows)
                            toggle("Errand Waiting Too Long", \.errandWaitingTooLong)
                            toggle("Log How Long It Took", \.logHowLongItTook)
                            ERNote(text: "Leave By is counted from the travel time and the buffer, not from the start of the window.")
                        }
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<NotificationPrefs, Bool>) -> some View {
        ERCard {
            ERToggleRow(title: title, isOn: Binding(
                get: { store.data.settings.notifications[keyPath: keyPath] },
                set: { newValue in store.mutate { $0.settings.notifications[keyPath: keyPath] = newValue } }
            ))
        }
    }
}

// MARK: - Data

struct DataSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var exportURLs: [URL] = []
    @State private var importing = false
    @State private var importError: String?
    @State private var importedNote: String?
    @State private var confirmClear = false
    @State private var confirmDelete = false

    var body: some View {
        ERScreen(sparkSeed: 29) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Data", onBack: { dismiss() })

                    ERCard {
                        VStack(alignment: .leading, spacing: 9) {
                            ERKeyValueRow(key: "Errands", value: "\(store.data.errands.count)")
                            ERKeyValueRow(key: "Places", value: "\(store.data.places.count)")
                            ERKeyValueRow(key: "Windows", value: "\(store.data.windows.count)")
                            ERKeyValueRow(key: "Runs", value: "\(store.data.runs.count)")
                            ERKeyValueRow(key: "Measured visits", value: "\(store.data.visits.count)")
                            ERKeyValueRow(key: "Wasted trips", value: "\(store.data.wastedTrips.count)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ERSectionHeader(text: "Export Data")
                        ERNote(text: "Errands and runs as CSV, a plain text summary, and a full backup file.")
                        if exportURLs.isEmpty {
                            Button("Prepare Export") {
                                exportURLs = Export.write(store.data)
                            }
                            .buttonStyle(FireButtonStyle())
                        } else {
                            ShareLink(items: exportURLs) {
                                Text("Share \(exportURLs.count) Files")
                                    .font(.erButton)
                                    .textCase(.uppercase)
                                    .foregroundStyle(ER.cherry)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: ERMetric.buttonHeight)
                                    .background { BeveledRect().fill(.fire) }
                            }
                            Button("Rebuild the Files") {
                                exportURLs = Export.write(store.data)
                            }
                            .buttonStyle(GhostButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ERSectionHeader(text: "Import Backup")
                        ERNote(text: "Replaces everything currently in the app with the contents of a backup file.")
                        Button("Choose a Backup File") { importing = true }
                            .buttonStyle(GhostButtonStyle())
                        if let importedNote {
                            Text(importedNote)
                                .font(.erCaption)
                                .foregroundStyle(ER.cherry)
                        }
                        if let importError {
                            ERErrorState(title: "Import Failed", message: importError)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ERSectionHeader(text: "Clear History")
                        ERNote(text: "Removes past runs, measurements and wasted trips. Errands, places and windows stay.")
                        Button("Clear History") { confirmClear = true }
                            .buttonStyle(GhostButtonStyle())
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ERSectionHeader(text: "Delete All App Data")
                        Button("Delete Everything") { confirmDelete = true }
                            .buttonStyle(CancelButtonStyle())
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    try store.importBackup(from: url)
                    importError = nil
                    importedNote = "Imported. \(store.data.errands.count) errands and \(store.data.places.count) places are in place."
                } catch {
                    importError = "That file could not be read as an Errand Run backup."
                }
            case .failure:
                importError = "No file was chosen."
            }
        }
        .alert("Clear the history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { store.clearHistory() }
        } message: {
            Text("Your measured times per place go with it, so the app starts learning again from scratch.")
        }
        .alert("Delete everything?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteEverything()
                dismiss()
            }
        } message: {
            Text("Every errand, place, window, run and photo is removed from this phone. It cannot be undone.")
        }
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ERScreen(sparkSeed: 30) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "About", onBack: { dismiss() })

                    ERCard(tone: .active) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Errand Run")
                                .font(.erCardTitle)
                                .foregroundStyle(ER.charcoal)
                            Text("A planner for ordinary errands, built around opening hours, real travel and the time you actually have.")
                                .font(.erBody)
                                .foregroundStyle(ER.charcoal.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ERCard(index: 1) {
                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "What It Promises")
                            bullet("Opening hours, lunch breaks and last entry are counted.")
                            bullet("Travel time comes from the device map service, once, then it is kept.")
                            bullet("What does not fit goes to the next window that does, and says when.")
                            bullet(AppMode.aboutStorageLine)
                        }
                    }

                    ERCard(index: 2, tone: .waiting) {
                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "What It Never Promises")
                            bullet("How long the queue will be. It records yours and plans with that instead.")
                            bullet("Anyone else's statistics for a place.")
                            bullet("That your data is anyone's but yours: it is never shared between accounts.")
                            bullet("That a route will survive contact with the day. That is what Running Late is for.")
                        }
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            DiamondShape()
                .fill(.fire)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            Text(text)
                .font(.erBody)
                .foregroundStyle(ER.charcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
