//
//  ChangeTracker.swift
//  ErrandRun
//
//  Works out what changed in the local store after every edit, so the sync engine
//  never has to guess and no call site has to remember to say "this is dirty".
//

import Foundation

protocol SyncableEntity: Identifiable, Hashable, Codable where ID == UUID {
    var updatedAt: Date? { get set }
}

extension Place: SyncableEntity {}
extension Errand: SyncableEntity {}
extension FreeWindow: SyncableEntity {}
extension Run: SyncableEntity {}
extension VisitLog: SyncableEntity {}
extension WastedTrip: SyncableEntity {}

enum ChangeTracker {
    struct Snapshot {
        var places: [UUID: Place] = [:]
        var errands: [UUID: Errand] = [:]
        var windows: [UUID: FreeWindow] = [:]
        var runs: [UUID: Run] = [:]
        var visits: [UUID: VisitLog] = [:]
        var wastedTrips: [UUID: WastedTrip] = [:]
        var travel: [String: TravelEntry] = [:]
        var settings = Settings()
    }

    static func snapshot(of data: AppData) -> Snapshot {
        Snapshot(
            places: index(data.places),
            errands: index(data.errands),
            windows: index(data.windows),
            runs: index(data.runs),
            visits: index(data.visits),
            wastedTrips: index(data.wastedTrips),
            travel: data.travel,
            settings: data.settings
        )
    }

    private static func index<T: SyncableEntity>(_ items: [T]) -> [UUID: T] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Stamps edits, records deletions and marks everything the server has not seen.
    static func apply(before: Snapshot, to data: inout AppData, at now: Date) {
        diff(\.places, before: before.places, collection: .places, now: now, in: &data)
        diff(\.errands, before: before.errands, collection: .errands, now: now, in: &data)
        diff(\.windows, before: before.windows, collection: .windows, now: now, in: &data)
        diff(\.runs, before: before.runs, collection: .runs, now: now, in: &data)
        diff(\.visits, before: before.visits, collection: .visits, now: now, in: &data)
        diff(\.wastedTrips, before: before.wastedTrips, collection: .wastedTrips, now: now, in: &data)
        diffTravel(before: before.travel, now: now, in: &data)

        if before.settings != data.settings {
            data.sync.settingsDirty = true
            data.sync.settingsUpdatedAt = now
        }
    }

    private static func diff<T: SyncableEntity>(
        _ path: WritableKeyPath<AppData, [T]>,
        before: [UUID: T],
        collection: SyncCollection,
        now: Date,
        in data: inout AppData
    ) {
        var items = data[keyPath: path]
        var present = Set<UUID>()
        var touched = false

        for index in items.indices {
            let id = items[index].id
            present.insert(id)
            if let old = before[id] {
                if old != items[index] {
                    items[index].updatedAt = now
                    data.dirty.mark(collection, id.uuidString)
                    touched = true
                }
            } else {
                items[index].updatedAt = now
                data.dirty.mark(collection, id.uuidString)
                touched = true
            }
        }

        if touched {
            data[keyPath: path] = items
        }

        for id in before.keys where !present.contains(id) {
            let key = id.uuidString
            data.tombstones.removeAll { $0.collection == collection && $0.id == key }
            data.tombstones.append(Tombstone(id: key, collection: collection, deletedAt: now))
            data.dirty.mark(collection, key)
        }
    }

    private static func diffTravel(before: [String: TravelEntry], now: Date, in data: inout AppData) {
        for (key, entry) in data.travel {
            if let old = before[key] {
                if old != entry {
                    data.travel[key]?.updatedAt = now
                    data.dirty.mark(.travelTimes, key)
                }
            } else {
                data.travel[key]?.updatedAt = now
                data.dirty.mark(.travelTimes, key)
            }
        }

        for key in before.keys where data.travel[key] == nil {
            data.tombstones.removeAll { $0.collection == .travelTimes && $0.id == key }
            data.tombstones.append(Tombstone(id: key, collection: .travelTimes, deletedAt: now))
            data.dirty.mark(.travelTimes, key)
        }
    }
}
