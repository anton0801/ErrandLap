//
//  AccountView.swift
//  ErrandRun
//
//  The account: who you are signed in as, which devices are signed in, and the two
//  buttons that end it — sign out and delete.
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(SyncEngine.self) private var sync
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [RemoteSession] = []
    @State private var loadingSessions = false
    @State private var sessionsError: String?

    @State private var showPasswordSheet = false
    @State private var showDeleteSheet = false
    @State private var showSignOutConfirm = false
    @State private var editingName = false
    @State private var nameDraft = ""

    var body: some View {
        ERScreen(sparkSeed: 35) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Account", onBack: { dismiss() })

                    identityCard
                    syncCard
                    devicesSection

                    VStack(spacing: 10) {
                        Button("Change Password") { showPasswordSheet = true }
                            .buttonStyle(GhostButtonStyle())
                        Button("Sign Out") { showSignOutConfirm = true }
                            .buttonStyle(GhostButtonStyle())
                        Button("Delete Account") { showDeleteSheet = true }
                            .buttonStyle(CancelButtonStyle())
                    }

                    ERNote(text: "Signing out removes the local copy from this phone. Everything comes back when you sign in again.")

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .task { await loadSessions() }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordChangeSheet().environment(auth)
        }
        .sheet(isPresented: $showDeleteSheet) {
            DeleteAccountSheet().environment(auth)
        }
        .alert("Sign out of this device?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { await auth.signOut() }
            }
        } message: {
            Text("Anything not yet synced is sent first if you are online.")
        }
    }

    // MARK: Cards

    private var identityCard: some View {
        ERCard(tone: .active) {
            VStack(alignment: .leading, spacing: 12) {
                ERSectionHeader(text: "Signed In As")
                Text(auth.email)
                    .font(.erCardTitle)
                    .foregroundStyle(ER.charcoal)
                    .fixedSize(horizontal: false, vertical: true)

                if editingName {
                    ERTextField(placeholder: "Your name", text: $nameDraft)
                    HStack(spacing: 10) {
                        Button("Save") {
                            Task {
                                if await auth.updateDisplayName(nameDraft.trimmingCharacters(in: .whitespaces)) {
                                    editingName = false
                                }
                            }
                        }
                        .buttonStyle(FireButtonStyle())
                        Button("Cancel") { editingName = false }
                            .buttonStyle(GhostButtonStyle())
                    }
                } else {
                    ERKeyValueRow(key: "Name", value: auth.displayName.isEmpty ? "Not set" : auth.displayName, mono: false)
                    if let since = auth.memberSince {
                        ERKeyValueRow(key: "Member since", value: ERTime.shortDate(since), mono: false)
                    }
                    Button("Edit Name") {
                        nameDraft = auth.displayName
                        editingName = true
                    }
                    .buttonStyle(GhostButtonStyle())
                }

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.erCaption)
                        .foregroundStyle(ER.scarlet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var syncCard: some View {
        ERCard(index: 1, tone: syncTone, glow: isSynced) {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "Sync")
                Text(syncSentence)
                    .font(.erBodyBold)
                    .foregroundStyle(ER.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                if sync.pendingCount > 0 {
                    ERKeyValueRow(key: "Waiting to send", value: "\(sync.pendingCount)")
                }
                Button("Sync Now") {
                    Task { await sync.syncNow() }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(sync.status.isBusy)
            }
        }
    }

    private var isSynced: Bool {
        if case .synced = sync.status { return true }
        return false
    }

    private var syncTone: ERStatusTone {
        switch sync.status {
        case .synced: return .done
        case .offline: return .waiting
        case .failed: return .active
        default: return .idle
        }
    }

    private var syncSentence: String {
        switch sync.status {
        case .idle:
            return store.data.sync.lastSyncedAt.map { "Last synced \(ERTime.stamp($0))." } ?? "Not synced yet."
        case .syncing:
            return "Sending and receiving…"
        case .synced(let date):
            return "Everything is in step. Last sync \(ERTime.stamp(date))."
        case .offline:
            return "Offline. Your edits are kept here and go up as soon as there is a connection."
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Signed-In Devices", trailing: sessions.isEmpty ? nil : "\(sessions.count)")

            if loadingSessions {
                ERLoadingState(text: "Loading devices")
            } else if let sessionsError {
                ERErrorState(title: "Could not load devices", message: sessionsError) {
                    Task { await loadSessions() }
                }
            } else if sessions.isEmpty {
                ERCard {
                    Text("No other device is signed in.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal.opacity(0.75))
                }
            } else {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    ERCard(index: index, tone: session.current ? .active : .idle) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(session.deviceName.isEmpty ? "Unknown device" : session.deviceName)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                Spacer(minLength: 6)
                                if session.current {
                                    ERTag(text: "This device", color: ER.scarlet)
                                }
                            }
                            if let used = session.lastUsedAt {
                                ERKeyValueRow(key: "Last used", value: ERTime.stamp(used))
                            }
                            if let ip = session.ipAddress {
                                ERKeyValueRow(key: "From", value: ip, mono: false)
                            }
                            if !session.current {
                                Button("Sign This Device Out") {
                                    Task {
                                        if await auth.revokeSession(id: session.id) {
                                            await loadSessions()
                                        }
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }
                }

                Button("Sign Out Everywhere") {
                    Task { await auth.signOut(everywhere: true) }
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private func loadSessions() async {
        loadingSessions = true
        sessionsError = nil
        defer { loadingSessions = false }
        do {
            sessions = try await auth.loadSessions()
        } catch let error as APIError {
            sessionsError = error.errorDescription
        } catch {
            sessionsError = error.localizedDescription
        }
    }
}

// MARK: - Password change

struct PasswordChangeSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var updated = ""
    @State private var keepOthers = false
    @State private var done = false

    var body: some View {
        ERScreen(sparkSeed: 36) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Change Password", onBack: { dismiss() })

                    if done {
                        ERCard(tone: .done, glow: true) {
                            Text("Password changed. Other devices were signed out.")
                                .font(.erBodyBold)
                                .foregroundStyle(ER.charcoal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Close") { dismiss() }
                            .buttonStyle(FireButtonStyle())
                    } else {
                        ERField("Current Password") {
                            SecureField("", text: $current, prompt: Text("Your password now")
                                .foregroundColor(ER.charcoal.opacity(0.35)))
                                .textContentType(.password)
                                .font(.erBody)
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background { BeveledRect(radius: 10, cap: 12).fill(ER.card) }
                                .overlay { BeveledRect(radius: 10, cap: 12).stroke(ER.charcoal, lineWidth: 2) }
                        }

                        ERField("New Password", hint: auth.fieldErrors["new_password"] ?? "At least 10 characters.") {
                            SecureField("", text: $updated, prompt: Text("The new one")
                                .foregroundColor(ER.charcoal.opacity(0.35)))
                                .textContentType(.newPassword)
                                .font(.erBody)
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background { BeveledRect(radius: 10, cap: 12).fill(ER.card) }
                                .overlay { BeveledRect(radius: 10, cap: 12).stroke(ER.charcoal, lineWidth: 2) }
                        }

                        ERCard {
                            ERToggleRow(title: "Keep other devices signed in",
                                        subtitle: "Off is safer: a password change usually means you want everything else out.",
                                        isOn: $keepOthers)
                        }

                        if let message = auth.errorMessage {
                            Text(message)
                                .font(.erCaption)
                                .foregroundStyle(ER.scarlet)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button("Change Password") {
                            Task {
                                if await auth.changePassword(current: current, new: updated, keepOtherSessions: keepOthers) {
                                    current = ""
                                    updated = ""
                                    done = true
                                }
                            }
                        }
                        .buttonStyle(FireButtonStyle())
                        .disabled(current.isEmpty || updated.count < 10 || auth.isWorking)

                        Button("Cancel") { dismiss() }
                            .buttonStyle(CancelButtonStyle())
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Account deletion

struct DeleteAccountSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var understood = false

    var body: some View {
        ERScreen(sparkSeed: 37) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Delete Account", onBack: { dismiss() })

                    ERCard(tone: .blocked) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("This cannot be undone.")
                                .font(.erCardTitle)
                                .foregroundStyle(ER.charcoal)
                            Text("Your errands, places, windows, runs and measured times are deleted from the server and from this phone. Nothing is kept but a record that an account was deleted, with your email stored only as a hash.")
                                .font(.erBody)
                                .foregroundStyle(ER.charcoal.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ERField("Your Password") {
                        SecureField("", text: $password, prompt: Text("Confirm it is you")
                            .foregroundColor(ER.charcoal.opacity(0.35)))
                            .textContentType(.password)
                            .font(.erBody)
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background { BeveledRect(radius: 10, cap: 12).fill(ER.card) }
                            .overlay { BeveledRect(radius: 10, cap: 12).stroke(ER.charcoal, lineWidth: 2) }
                    }

                    ERCard {
                        ERToggleRow(title: "I understand this deletes everything", isOn: $understood)
                    }

                    if let message = auth.errorMessage {
                        Text(message)
                            .font(.erCaption)
                            .foregroundStyle(ER.scarlet)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Delete My Account") {
                        Task {
                            if await auth.deleteAccount(password: password) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(CancelButtonStyle())
                    .disabled(password.isEmpty || !understood || auth.isWorking)

                    Button("Keep My Account") { dismiss() }
                        .buttonStyle(FireButtonStyle())

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
