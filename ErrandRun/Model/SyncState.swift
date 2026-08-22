//
//  SyncState.swift
//  ErrandRun
//
//  What the device still owes the server, and what it has already heard from it.
//

import Foundation

enum SyncCollection: String, Codable, CaseIterable, Hashable {
    case places
    case errands
    case windows
    case runs
    case visits
    case wastedTrips
    case travelTimes

    /// The path segment the API uses.
    var path: String {
        switch self {
        case .places: return "places"
        case .errands: return "errands"
        case .windows: return "windows"
        case .runs: return "runs"
        case .visits: return "visits"
        case .wastedTrips: return "wasted-trips"
        case .travelTimes: return "travel-times"
        }
    }
}

/// A record of something deleted here, kept until the server has been told.
struct Tombstone: Codable, Hashable, Identifiable {
    var id: String
    var collection: SyncCollection
    var deletedAt: Date

    var key: String { "\(collection.rawValue)/\(id)" }
}

/// Ids edited locally and not yet accepted by the server.
struct DirtyIndex: Codable, Hashable {
    private var storage: [String: [String]] = [:]

    var isEmpty: Bool { storage.values.allSatisfy(\.isEmpty) }

    var count: Int { storage.values.reduce(0) { $0 + $1.count } }

    func ids(_ collection: SyncCollection) -> [String] {
        storage[collection.rawValue] ?? []
    }

    mutating func mark(_ collection: SyncCollection, _ id: String) {
        var list = storage[collection.rawValue] ?? []
        if !list.contains(id) {
            list.append(id)
            storage[collection.rawValue] = list
        }
    }

    mutating func clear(_ collection: SyncCollection, _ ids: [String]) {
        guard var list = storage[collection.rawValue] else { return }
        let removed = Set(ids)
        list.removeAll { removed.contains($0) }
        storage[collection.rawValue] = list
    }

    mutating func clearAll() {
        storage = [:]
    }
}

struct SyncState: Codable, Hashable {
    /// Which account this local copy belongs to. A different one means a clean slate.
    var accountID: String?
    /// The server clock at the last successful exchange; the next delta starts here.
    var cursor: Date?
    var lastSyncedAt: Date?
    var lastError: String?
    var settingsDirty: Bool = false
    var settingsUpdatedAt: Date?

    var hasSynced: Bool { lastSyncedAt != nil }
}
