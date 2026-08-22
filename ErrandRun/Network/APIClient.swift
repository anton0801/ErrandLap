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

enum APIConfiguration {
    /// Point this at your deployment. Only the development default is plain HTTP,
    /// and only because loopback never leaves the device.
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "ERAPIBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:8799")!
        #else
        return URL(string: "https://errand-application.online")!
        #endif
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

    private func clearSessionAndNotify() {
        setSession(nil)
        onSessionLost?()
    }
}

struct EmptyResponse: Decodable {}
