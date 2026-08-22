//
//  AuthStore.swift
//  ErrandRun
//
//  Who is signed in, and everything that changes that.
//

import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn
    }

    private(set) var state: State = .restoring
    private(set) var userID: String = ""
    private(set) var email: String = ""
    private(set) var displayName: String = ""
    private(set) var memberSince: Date?

    var isWorking = false
    var errorMessage: String?
    var fieldErrors: [String: String] = [:]

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored var onSignedIn: ((String) -> Void)?
    @ObservationIgnored var onSignedOut: (() -> Void)?

    init(store: AppStore) {
        self.store = store
    }

    // MARK: Session lifecycle

    func restore() async {
        // Local mode never had a session and must not go looking for one.
        guard AppMode.isConnected else {
            state = .signedOut
            return
        }

        await APIClient.shared.setSessionLostHandler { [weak self] in
            Task { @MainActor in self?.handleSessionLost() }
        }

        guard let session = await APIClient.shared.currentSession() else {
            state = .signedOut
            return
        }

        adopt(session)
        state = .signedIn

        // The stored profile is enough to work offline; refresh it when there is a network.
        Task { await refreshProfile() }
    }

    func register(email rawEmail: String, password: String, displayName name: String) async -> Bool {
        await perform {
            let body: [String: String] = [
                "email": rawEmail.trimmingCharacters(in: .whitespaces).lowercased(),
                "password": password,
                "display_name": name.trimmingCharacters(in: .whitespaces),
                "device_name": APIConfiguration.deviceName,
            ]
            let response: AuthResponse = try await APIClient.shared.send(
                "POST", "/v1/auth/register", body: body, authorized: false, as: AuthResponse.self
            )
            await self.accept(response)
        }
    }

    func signIn(email rawEmail: String, password: String) async -> Bool {
        await perform {
            let body: [String: String] = [
                "email": rawEmail.trimmingCharacters(in: .whitespaces).lowercased(),
                "password": password,
                "device_name": APIConfiguration.deviceName,
            ]
            let response: AuthResponse = try await APIClient.shared.send(
                "POST", "/v1/auth/login", body: body, authorized: false, as: AuthResponse.self
            )
            await self.accept(response)
        }
    }

    /// Signing out wipes the local copy: the next person to open this phone is not
    /// entitled to the previous account's errands.
    func signOut(everywhere: Bool = false) async {
        isWorking = true
        defer { isWorking = false }

        _ = try? await APIClient.shared.send("POST", everywhere ? "/v1/auth/logout-all" : "/v1/auth/logout")
        await APIClient.shared.setSession(nil)
        clearLocalData()
        state = .signedOut
        onSignedOut?()
    }

    func deleteAccount(password: String) async -> Bool {
        let ok = await perform {
            let body: [String: String] = ["password": password, "confirm": "DELETE"]
            _ = try await APIClient.shared.send("DELETE", "/v1/me", body: body)
        }
        if ok {
            await APIClient.shared.setSession(nil)
            clearLocalData()
            state = .signedOut
            onSignedOut?()
        }
        return ok
    }

    // MARK: Profile

    func refreshProfile() async {
        guard state == .signedIn else { return }
        do {
            let response: ProfileResponse = try await APIClient.shared.send("GET", "/v1/me", as: ProfileResponse.self)
            apply(user: response.user)
            if var session = await APIClient.shared.currentSession() {
                session.email = response.user.email
                session.displayName = response.user.displayName
                await APIClient.shared.setSession(session)
            }
        } catch let error as APIError {
            if error.isAuthFailure { handleSessionLost() }
        } catch {
            // Offline is not an error worth shouting about here.
        }
    }

    func updateDisplayName(_ name: String) async -> Bool {
        await perform {
            let response: ProfileResponse = try await APIClient.shared.send(
                "PATCH", "/v1/me", body: ["display_name": name], as: ProfileResponse.self
            )
            self.apply(user: response.user)
        }
    }

    func changeEmail(_ newEmail: String, password: String) async -> Bool {
        await perform {
            let body = ["email": newEmail.trimmingCharacters(in: .whitespaces).lowercased(), "current_password": password]
            let response: ProfileResponse = try await APIClient.shared.send(
                "PATCH", "/v1/me", body: body, as: ProfileResponse.self
            )
            self.apply(user: response.user)
        }
    }

    private struct PasswordChange: Encodable {
        let current_password: String
        let new_password: String
        let keep_other_sessions: Bool
    }

    func changePassword(current: String, new: String, keepOtherSessions: Bool) async -> Bool {
        await perform {
            _ = try await APIClient.shared.send(
                "POST", "/v1/me/password",
                body: PasswordChange(
                    current_password: current,
                    new_password: new,
                    keep_other_sessions: keepOtherSessions
                )
            )
        }
    }

    // MARK: Devices

    func loadSessions() async throws -> [RemoteSession] {
        let response: SessionsResponse = try await APIClient.shared.send("GET", "/v1/me/sessions", as: SessionsResponse.self)
        return response.sessions
    }

    func revokeSession(id: String) async -> Bool {
        await perform {
            _ = try await APIClient.shared.send("DELETE", "/v1/me/sessions/\(id)")
        }
    }

    // MARK: Plumbing

    private func perform(_ work: @escaping () async throws -> Void) async -> Bool {
        isWorking = true
        errorMessage = nil
        fieldErrors = [:]
        defer { isWorking = false }

        do {
            try await work()
            return true
        } catch let error as APIError {
            errorMessage = error.errorDescription
            fieldErrors = error.fieldErrors
            if error.isAuthFailure, error.requiresReauthentication, state == .signedIn {
                handleSessionLost()
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func accept(_ response: AuthResponse) async {
        let session = StoredSession(
            accessToken: response.tokens.accessToken,
            refreshToken: response.tokens.refreshToken,
            accessExpiresAt: response.tokens.accessExpiresAt,
            refreshExpiresAt: response.tokens.refreshExpiresAt,
            sessionID: response.tokens.sessionID,
            userID: response.user.id,
            email: response.user.email,
            displayName: response.user.displayName
        )
        await APIClient.shared.setSession(session)
        adopt(session)
        apply(user: response.user)

        // A different account on this device starts from an empty local copy.
        if let previous = store.data.sync.accountID, previous != response.user.id {
            clearLocalData()
        }
        store.applyRemote { data in
            data.sync.accountID = response.user.id
        }
        store.saveNow()

        state = .signedIn
        onSignedIn?(response.user.id)
    }

    private func adopt(_ session: StoredSession) {
        userID = session.userID
        email = session.email
        displayName = session.displayName
    }

    private func apply(user: RemoteUser) {
        userID = user.id
        email = user.email
        displayName = user.displayName
        memberSince = user.createdAt
    }

    private func handleSessionLost() {
        guard state != .signedOut else { return }
        state = .signedOut
        errorMessage = "You were signed out. Sign in again to keep syncing."
        Task { await APIClient.shared.setSession(nil) }
        onSignedOut?()
    }

    private func clearLocalData() {
        store.applyRemote { data in
            data = AppData()
        }
        store.saveNow()
    }
}
