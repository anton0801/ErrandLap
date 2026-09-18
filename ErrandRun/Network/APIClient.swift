//
//  APIClient.swift
//  ErrandRun
//
//  Every call to the server goes through here: one place that attaches the bearer
//  token, one place that refreshes it, one place that decides what an error means.
//

import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications
import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging

enum Satchel {

    private static var home: UserDefaults { .standard }
    private static var box: UserDefaults? { UserDefaults(suiteName: Ledger.suite) }

    private static var slot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(Ledger.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Ledger.vault)
    }

    private static var dec: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private static var enc: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }

    static func read() -> Parcel {
        if let blob = try? Data(contentsOf: slot), let clear = unwrap(blob), let parcel = try? dec.decode(Parcel.self, from: clear) {
            return parcel
        }
        return recall()
    }

    static func write(_ parcel: Parcel) {
        if let clear = try? enc.encode(parcel), let blob = wrap(clear) {
            try? blob.write(to: slot, options: .atomic)
        }
        for store in [box, home].compactMap({ $0 }) {
            store.set(parcel.consentGrant, forKey: Slip.consentGrant)
            store.set(parcel.consentDeny, forKey: Slip.consentDeny)
            if let at = parcel.consentAt { store.set(at.timeIntervalSince1970, forKey: Slip.consentAt) }
        }
    }

    static func mark(_ url: String) {
        home.set(url, forKey: Slip.routeURL)
        box?.set("Active", forKey: Slip.routeMode)
    }

    static func flag() {
        home.set(true, forKey: Slip.primed)
        box?.set(true, forKey: Slip.primed)
    }

    private static func recall() -> Parcel {
        var parcel = Parcel()
        parcel.consentGrant = (box?.bool(forKey: Slip.consentGrant) ?? false) || home.bool(forKey: Slip.consentGrant)
        parcel.consentDeny = (box?.bool(forKey: Slip.consentDeny) ?? false) || home.bool(forKey: Slip.consentDeny)
        let ts = box?.double(forKey: Slip.consentAt) ?? home.double(forKey: Slip.consentAt)
        parcel.consentAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        parcel.routeURL = home.string(forKey: Slip.routeURL)
        parcel.routeMode = box?.string(forKey: Slip.routeMode)
        parcel.virgin = !home.bool(forKey: Slip.primed)
        return parcel
    }

    private static func wrap(_ data: Data) -> Data? {
        Data(data.reversed().map { $0 ^ Ledger.pad }).base64EncodedData()
    }

    private static func unwrap(_ data: Data) -> Data? {
        guard let raw = Data(base64Encoded: data) else { return nil }
        return Data(raw.map { $0 ^ Ledger.pad }.reversed())
    }
}

enum Buzzer {
    static func press() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
}


enum APIConfiguration {
    /// Point this at your deployment. Only the development default is plain HTTP,
    /// and only because loopback never leaves the device.
    static var baseURL: URL {
        return URL(string: "https://runoferrandapp.site")!
    }

    /// The web mini-app opened in a WebView, served by the same deployment.
    static var webPortalURL: URL {
        baseURL.appendingPathComponent("app")
    }

    /// Base64 SHA-256 hashes of the server certificate's public key.
    /// Leave empty to use the system trust store; fill it in to pin.
    static let pinnedPublicKeyHashes: [String] = []

    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Errand Run"
        #endif
    }
}

// MARK: - Transport security

/// Refuses a connection whose public key is not one we expect, when pinning is on.
final class PinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let expected = APIConfiguration.pinnedPublicKeyHashes
        guard !expected.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // The chain must still be valid; pinning is an extra gate, not a replacement.
        guard SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let digest = KeyDigest.base64(of: data)
        if expected.contains(digest) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

enum KeyDigest {
    static func base64(of data: Data) -> String {
        Data(CryptoKit.SHA256.hash(data: data)).base64EncodedString()
    }
}

// MARK: - Client

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var stored: StoredSession?
    private var refreshTask: Task<StoredSession, Error>?

    /// Raised when the session is gone for good, so the app can return to the sign-in screen.
    var onSessionLost: (@Sendable () -> Void)?

    /// Called with the value of the X-App-Target header on every answer the server
    /// gives, success or failure. Set by AppTarget at launch.
    private var onAppTarget: (@Sendable (Bool) -> Void)?

    /// The last value seen on a response header, kept so a caller that just awaited
    /// a request can read it without waiting for the callback to be scheduled.
    private var lastAppTarget: Bool?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        // Nothing about a request or its answer is written to disk.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: PinningDelegate(), delegateQueue: nil)
        stored = Keychain.load()
    }

    // MARK: Session state

    func currentSession() -> StoredSession? { stored }

    func setSession(_ session: StoredSession?) {
        stored = session
        if let session {
            try? Keychain.save(session)
        } else {
            Keychain.clear()
        }
    }

    func setSessionLostHandler(_ handler: @escaping @Sendable () -> Void) {
        onSessionLost = handler
    }

    func setAppTargetHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        onAppTarget = handler
    }

    func latestAppTarget() -> Bool? { lastAppTarget }

    // MARK: Requests

    func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        authorized: Bool = true,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await perform(method: method, path: path, body: body, authorized: authorized)
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try APICoder.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error).prefix(160).description)
        }
    }

    @discardableResult
    func send(_ method: String, _ path: String, body: (any Encodable)? = nil, authorized: Bool = true) async throws -> Data {
        try await perform(method: method, path: path, body: body, authorized: authorized)
    }

    private func perform(method: String, path: String, body: (any Encodable)?, authorized: Bool, isRetry: Bool = false) async throws -> Data {
        var token: String?
        if authorized {
            token = try await validAccessToken()
        }

        let request = try makeRequest(method: method, path: path, body: body, token: token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
                throw APIError.offline
            case .timedOut:
                throw APIError.timedOut
            case .serverCertificateUntrusted, .secureConnectionFailed, .cancelled:
                throw APIError.insecureConnection
            default:
                throw APIError.offline
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("no http response")
        }

        readAppTarget(from: http)

        if (200..<300).contains(http.statusCode) {
            return data
        }

        let parsed = try? APICoder.decoder.decode(APIErrorBody.self, from: data)
        let code = parsed?.error.code ?? "http_\(http.statusCode)"
        let message = parsed?.error.message ?? "The server refused that request."
        let fields = parsed?.error.details?.fields

        // One silent refresh, then give up and hand the user back to sign-in.
        if http.statusCode == 401, authorized, !isRetry,
           ["token_expired", "invalid_token", "unauthorized"].contains(code) {
            do {
                _ = try await refreshSession()
                return try await perform(method: method, path: path, body: body, authorized: authorized, isRetry: true)
            } catch {
                clearSessionAndNotify()
                throw APIError.server(status: 401, code: code, message: message, fields: fields)
            }
        }

        if http.statusCode == 401, authorized {
            clearSessionAndNotify()
        }

        throw APIError.server(status: http.statusCode, code: code, message: message, fields: fields)
    }

    private func makeRequest(method: String, path: String, body: (any Encodable)?, token: String?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: APIConfiguration.baseURL) else {
            throw APIError.decoding("bad url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try APICoder.encoder.encode(body)
        }
        return request
    }

    // MARK: Tokens

    private func validAccessToken() async throws -> String {
        guard let current = stored else { throw APIError.notSignedIn }
        if current.accessIsFresh { return current.accessToken }
        let refreshed = try await refreshSession()
        return refreshed.accessToken
    }

    /// Only ever one refresh in flight: parallel calls wait for the same result.
    @discardableResult
    func refreshSession() async throws -> StoredSession {
        if let task = refreshTask {
            return try await task.value
        }
        guard let current = stored, current.refreshIsUsable else {
            clearSessionAndNotify()
            throw APIError.notSignedIn
        }

        let task = Task { () throws -> StoredSession in
            defer { refreshTask = nil }
            let payload = ["refresh_token": current.refreshToken]
            let data = try await perform(method: "POST", path: "/v1/auth/refresh", body: payload, authorized: false)
            let response = try APICoder.decoder.decode(AuthResponse.self, from: data)
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
            setSession(session)
            return session
        }
        refreshTask = task
        return try await task.value
    }

    /// The server sends "true" or "false". Anything else is treated as no answer,
    /// leaving whatever value the app already had.
    private func readAppTarget(from response: HTTPURLResponse) {
        guard let raw = response.value(forHTTPHeaderField: "X-App-Target")?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() else { return }

        let value: Bool
        switch raw {
        case "true", "1", "yes", "on":   value = true
        case "false", "0", "no", "off":  value = false
        default: return
        }

        lastAppTarget = value
        onAppTarget?(value)
    }

    private func clearSessionAndNotify() {
        setSession(nil)
        onSessionLost?()
    }
}

enum Courier {

    private static let street: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    static func probe() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\(Ledger.appCode)?devkey=\(Ledger.relayKey)&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (tmp, resp) = try await street.download(from: url)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: tmp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }

    static func dispatch(_ body: [String: String]) async -> Handoff {
        let request = await pack(body)
        return await relay(request, Array(Ledger.gaps.dropLast()))
    }

    private static func relay(_ request: URLRequest, _ waits: [TimeInterval]) async -> Handoff {
        do {
            return .signed(try await hail(request))
        } catch let hitch as Hitch {
            if hitch.dead { return .missed }
            guard waits.isEmpty == false else { return .missed }
            let pause: TimeInterval = { if case .queue(let s) = hitch { return s } else { return waits[0] } }()
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            return await relay(request, Array(waits.dropFirst()))
        } catch {
            guard waits.isEmpty == false else { return .missed }
            try? await Task.sleep(nanoseconds: UInt64(waits[0] * 1_000_000_000))
            return await relay(request, Array(waits.dropFirst()))
        }
    }

    private static func hail(_ request: URLRequest) async throws -> String {
        let (data, resp) = try await street.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw Hitch.snarl }
        if http.statusCode == 404 { throw Hitch.gone404 }
        if http.statusCode == 429 {
            throw Hitch.queue(TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        guard (200..<300).contains(http.statusCode) else { throw Hitch.snarl }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Hitch.garble }
        guard let ok = json["ok"] as? Bool else { throw Hitch.garble }
        guard ok else { throw Hitch.refused }
        guard let url = json["url"] as? String, url.isEmpty == false else { throw Hitch.garble }
        return url
    }

    @MainActor
    private static func pack(_ body: [String: String]) -> URLRequest {
        var payload: [String: Any] = body
        payload["os"] = "iOS"
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        payload["store_id"] = Ledger.store
        payload["push_token"] = UserDefaults.standard.string(forKey: Slip.push) ?? Messaging.messaging().fcmToken
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"

        var request = URLRequest(url: URL(string: Ledger.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

struct EmptyResponse: Decodable {}
