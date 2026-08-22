//
//  APIModels.swift
//  ErrandRun
//
//  The wire format. Field names are explicit rather than derived, so the payload
//  inside each item keeps the app's own camelCase keys untouched.
//

import Foundation

// MARK: - Coders

enum APICoder {
    /// The server sends ISO-8601 with milliseconds; older rows may have none.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return encoder
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso(_ date: Date) -> String { fractional.string(from: date) }
}

// MARK: - Errors

struct APIErrorBody: Decodable {
    struct Payload: Decodable {
        var code: String
        var message: String
        var details: Details?
    }

    struct Details: Decodable {
        var fields: [String: String]?
        var retryAfter: Int?

        enum CodingKeys: String, CodingKey {
            case fields
            case retryAfter = "retry_after"
        }
    }

    var error: Payload
}

enum APIError: LocalizedError {
    case offline
    case timedOut
    case notSignedIn
    case server(status: Int, code: String, message: String, fields: [String: String]?)
    case decoding(String)
    case insecureConnection

    var errorDescription: String? {
        switch self {
        case .offline:
            return "No connection. Your errands are still here — they will sync when you are back online."
        case .timedOut:
            return "The server took too long to answer. Try again in a moment."
        case .notSignedIn:
            return "You are signed out. Sign in again to sync."
        case .server(_, _, let message, _):
            return message
        case .decoding(let detail):
            return "The server sent something unexpected. (\(detail))"
        case .insecureConnection:
            return "The connection could not be verified and was refused."
        }
    }

    /// The field-level messages a form should show next to its inputs.
    var fieldErrors: [String: String] {
        if case .server(_, _, _, let fields) = self { return fields ?? [:] }
        return [:]
    }

    var code: String {
        if case .server(_, let code, _, _) = self { return code }
        return "network"
    }

    var isAuthFailure: Bool {
        if case .server(let status, _, _, _) = self { return status == 401 }
        return false
    }

    var requiresReauthentication: Bool {
        ["invalid_token", "session_revoked", "refresh_reuse", "account_deleted", "token_expired"].contains(code)
    }
}

// MARK: - Auth payloads

struct TokenPair: Decodable {
    var sessionID: String
    var accessToken: String
    var refreshToken: String
    var accessExpiresAt: Date
    var refreshExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accessExpiresAt = "access_expires_at"
        case refreshExpiresAt = "refresh_expires_at"
    }
}

struct RemoteUser: Decodable {
    var id: String
    var email: String
    var displayName: String
    var createdAt: Date?
    var passwordChangedAt: Date?
    var emailVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case createdAt = "created_at"
        case passwordChangedAt = "password_changed_at"
        case emailVerified = "email_verified"
    }
}

struct AuthResponse: Decodable {
    var user: RemoteUser
    var tokens: TokenPair
}

struct ProfileResponse: Decodable {
    var user: RemoteUser
    var counts: [String: Int]?
}

struct RemoteSession: Decodable, Identifiable {
    var id: String
    var deviceName: String
    var userAgent: String?
    var ipAddress: String?
    var createdAt: Date?
    var lastUsedAt: Date?
    var expiresAt: Date?
    var current: Bool

    enum CodingKeys: String, CodingKey {
        case id, current
        case deviceName = "device_name"
        case userAgent = "user_agent"
        case ipAddress = "ip_address"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case expiresAt = "expires_at"
    }
}

struct SessionsResponse: Decodable {
    var sessions: [RemoteSession]
}

// MARK: - Sync payloads

/// One record on the wire. `payload` is the app's own model, encoded as it is stored.
struct SyncItem<Model: Codable>: Codable {
    var id: String
    var updatedAt: Date
    var deleted: Bool
    var payload: Model?

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
        case deleted
        case payload
    }

    init(id: String, updatedAt: Date, deleted: Bool, payload: Model?) {
        self.id = id
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        // A tombstone carries an empty object where the model would be.
        payload = deleted ? nil : try? container.decode(Model.self, forKey: .payload)
    }
}

struct SyncSettingsItem: Codable {
    var updatedAt: Date
    var payload: Settings?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case payload
    }

    init(updatedAt: Date, payload: Settings?) {
        self.updatedAt = updatedAt
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        payload = try? container.decode(Settings.self, forKey: .payload)
    }
}

struct SyncPush: Encodable {
    var since: String?
    var settings: SyncSettingsItem?
    var places: [SyncItem<Place>]?
    var errands: [SyncItem<Errand>]?
    var windows: [SyncItem<FreeWindow>]?
    var runs: [SyncItem<Run>]?
    var visits: [SyncItem<VisitLog>]?
    var wastedTrips: [SyncItem<WastedTrip>]?
    var travelTimes: [SyncItem<TravelEntry>]?

    enum CodingKeys: String, CodingKey {
        case since, settings, places, errands, windows, runs, visits
        case wastedTrips = "wasted-trips"
        case travelTimes = "travel-times"
    }

    var count: Int {
        var total = settings == nil ? 0 : 1
        total += places?.count ?? 0
        total += errands?.count ?? 0
        total += windows?.count ?? 0
        total += runs?.count ?? 0
        total += visits?.count ?? 0
        total += wastedTrips?.count ?? 0
        total += travelTimes?.count ?? 0
        return total
    }

    var isEmpty: Bool { count == 0 }
}

struct SyncDelta: Decodable {
    var serverTime: Date
    var settings: SyncSettingsItem?
    var places: [SyncItem<Place>]
    var errands: [SyncItem<Errand>]
    var windows: [SyncItem<FreeWindow>]
    var runs: [SyncItem<Run>]
    var visits: [SyncItem<VisitLog>]
    var wastedTrips: [SyncItem<WastedTrip>]
    var travelTimes: [SyncItem<TravelEntry>]

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case settings, places, errands, windows, runs, visits
        case wastedTrips = "wasted-trips"
        case travelTimes = "travel-times"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverTime = try container.decodeIfPresent(Date.self, forKey: .serverTime) ?? Date()
        settings = try? container.decode(SyncSettingsItem.self, forKey: .settings)
        places = (try? container.decode([SyncItem<Place>].self, forKey: .places)) ?? []
        errands = (try? container.decode([SyncItem<Errand>].self, forKey: .errands)) ?? []
        windows = (try? container.decode([SyncItem<FreeWindow>].self, forKey: .windows)) ?? []
        runs = (try? container.decode([SyncItem<Run>].self, forKey: .runs)) ?? []
        visits = (try? container.decode([SyncItem<VisitLog>].self, forKey: .visits)) ?? []
        wastedTrips = (try? container.decode([SyncItem<WastedTrip>].self, forKey: .wastedTrips)) ?? []
        travelTimes = (try? container.decode([SyncItem<TravelEntry>].self, forKey: .travelTimes)) ?? []
    }

    var totalItems: Int {
        places.count + errands.count + windows.count + runs.count
            + visits.count + wastedTrips.count + travelTimes.count
    }
}
