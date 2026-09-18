//
//  SyncEngine.swift
//  ErrandRun
//
//  Keeps the local copy and the account in step. The phone stays the source of
//  truth for what you just typed; the server is what makes it survive a new device.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SyncEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case offline
        case failed(String)

        var isBusy: Bool { self == .syncing }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var pendingCount: Int = 0

    private let store: AppStore
    private var runningTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var enabled = false

    init(store: AppStore) {
        self.store = store
        pendingCount = store.data.dirty.count
    }

    // MARK: Lifecycle

    func attach() {
        store.onLocalChange = { [weak self] in
            guard let self else { return }
            self.pendingCount = self.store.data.dirty.count
            self.scheduleSync()
        }
    }

    func enable() {
        // The one place that decides whether this engine ever runs.
        guard AppMode.isConnected else {
            enabled = false
            return
        }
        enabled = true
        Task { await syncNow() }
    }

    func disable() {
        enabled = false
        debounceTask?.cancel()
        runningTask?.cancel()
        status = .idle
        pendingCount = 0
    }

    /// Called after every local edit; waits for the typing to stop before talking.
    private func scheduleSync() {
        guard enabled else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow(fullPull: Bool = false) async {
        guard enabled else { return }
        if let running = runningTask {
            await running.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.exchange(fullPull: fullPull)
        }
        runningTask = task
        await task.value
        runningTask = nil
    }

    // MARK: The exchange

    private func exchange(fullPull: Bool) async {
        status = .syncing

        let since = fullPull ? nil : store.data.sync.cursor
        let (push, stamps) = buildPush(since: since)

        do {
            let delta: SyncDelta
            if push.isEmpty {
                let query = since.map { "?since=\(APICoder.iso($0).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" } ?? ""
                delta = try await APIClient.shared.send("GET", "/v1/sync\(query)", as: SyncDelta.self)
            } else {
                delta = try await APIClient.shared.send("POST", "/v1/sync", body: push, as: SyncDelta.self)
            }

            apply(delta: delta, acknowledged: stamps)
            store.saveNow()
            pendingCount = store.data.dirty.count
            status = .synced(Date())
        } catch let error as APIError {
            switch error {
            case .offline, .timedOut:
                status = .offline
            case .notSignedIn:
                status = .idle
            default:
                status = .failed(error.errorDescription ?? "Sync failed.")
            }
            store.applyRemote { data in
                data.sync.lastError = error.errorDescription
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Building the push

    private typealias Stamps = [SyncCollection: [String: Date]]

    private func buildPush(since: Date?) -> (SyncPush, Stamps) {
        let data = store.data
        var push = SyncPush()
        var stamps: Stamps = [:]
        push.since = since.map(APICoder.iso)

        func items<T: SyncableEntity>(_ collection: SyncCollection, _ list: [T]) -> [SyncItem<T>] {
            let index = Dictionary(list.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
            var result: [SyncItem<T>] = []
            var recorded: [String: Date] = [:]

            for id in data.dirty.ids(collection) {
                if let entity = index[id] {
                    let stamp = entity.updatedAt ?? Date()
                    result.append(SyncItem(id: id, updatedAt: stamp, deleted: false, payload: entity))
                    recorded[id] = stamp
                } else if let tomb = data.tombstones.first(where: { $0.collection == collection && $0.id == id }) {
                    result.append(SyncItem(id: id, updatedAt: tomb.deletedAt, deleted: true, payload: nil))
                    recorded[id] = tomb.deletedAt
                }
            }
            if !recorded.isEmpty { stamps[collection] = recorded }
            return result
        }

        push.places = items(.places, data.places)
        push.errands = items(.errands, data.errands)
        push.windows = items(.windows, data.windows)
        push.runs = items(.runs, data.runs)
        push.visits = items(.visits, data.visits)
        push.wastedTrips = items(.wastedTrips, data.wastedTrips)

        var travelItems: [SyncItem<TravelEntry>] = []
        var travelStamps: [String: Date] = [:]
        for key in data.dirty.ids(.travelTimes) {
            if let entry = data.travel[key] {
                travelItems.append(SyncItem(id: key, updatedAt: entry.updatedAt, deleted: false, payload: entry))
                travelStamps[key] = entry.updatedAt
            } else if let tomb = data.tombstones.first(where: { $0.collection == .travelTimes && $0.id == key }) {
                travelItems.append(SyncItem(id: key, updatedAt: tomb.deletedAt, deleted: true, payload: nil))
                travelStamps[key] = tomb.deletedAt
            }
        }
        if !travelStamps.isEmpty { stamps[.travelTimes] = travelStamps }
        push.travelTimes = travelItems

        if data.sync.settingsDirty {
            push.settings = SyncSettingsItem(
                updatedAt: data.sync.settingsUpdatedAt ?? Date(),
                payload: data.settings
            )
        }

        return (push, stamps)
    }

    // MARK: Applying the delta

    private func apply(delta: SyncDelta, acknowledged: Stamps) {
        let settingsStamp = store.data.sync.settingsUpdatedAt

        store.applyRemote { data in
            // Settings: the newer edit wins, exactly as on the server.
            if let remote = delta.settings, let payload = remote.payload {
                let localIsNewer = data.sync.settingsDirty
                    && (data.sync.settingsUpdatedAt ?? .distantPast) > remote.updatedAt
                if !localIsNewer {
                    data.settings = payload
                }
            }

            merge(delta.places, into: \.places, collection: .places, data: &data)
            merge(delta.errands, into: \.errands, collection: .errands, data: &data)
            merge(delta.windows, into: \.windows, collection: .windows, data: &data)
            merge(delta.runs, into: \.runs, collection: .runs, data: &data)
            merge(delta.visits, into: \.visits, collection: .visits, data: &data)
            merge(delta.wastedTrips, into: \.wastedTrips, collection: .wastedTrips, data: &data)
            mergeTravel(delta.travelTimes, data: &data)

            // Anything still carrying the timestamp we sent has been accepted.
            for (collection, sent) in acknowledged {
                var settled: [String] = []
                for (id, stamp) in sent where currentStamp(for: id, collection: collection, in: data) == stamp
                    || currentStamp(for: id, collection: collection, in: data) == nil {
                    settled.append(id)
                    data.tombstones.removeAll { $0.collection == collection && $0.id == id && $0.deletedAt <= stamp }
                }
                data.dirty.clear(collection, settled)
            }

            if let stamp = settingsStamp, data.sync.settingsUpdatedAt == stamp {
                data.sync.settingsDirty = false
            } else if settingsStamp == nil {
                data.sync.settingsDirty = false
            }

            data.sync.cursor = delta.serverTime
            data.sync.lastSyncedAt = Date()
            data.sync.lastError = nil
        }
    }

    private func currentStamp(for id: String, collection: SyncCollection, in data: AppData) -> Date? {
        switch collection {
        case .places: return data.places.first { $0.id.uuidString == id }?.updatedAt
        case .errands: return data.errands.first { $0.id.uuidString == id }?.updatedAt
        case .windows: return data.windows.first { $0.id.uuidString == id }?.updatedAt
        case .runs: return data.runs.first { $0.id.uuidString == id }?.updatedAt
        case .visits: return data.visits.first { $0.id.uuidString == id }?.updatedAt
        case .wastedTrips: return data.wastedTrips.first { $0.id.uuidString == id }?.updatedAt
        case .travelTimes: return data.travel[id]?.updatedAt
        }
    }

    private func merge<T: SyncableEntity>(
        _ items: [SyncItem<T>],
        into path: WritableKeyPath<AppData, [T]>,
        collection: SyncCollection,
        data: inout AppData
    ) {
        guard !items.isEmpty else { return }
        let dirty = Set(data.dirty.ids(collection))

        for item in items {
            guard let id = UUID(uuidString: item.id) else { continue }
            let localIndex = data[keyPath: path].firstIndex { $0.id == id }
            let localStamp = localIndex.map { data[keyPath: path][$0].updatedAt ?? .distantPast }
            let localWins = dirty.contains(item.id) && (localStamp ?? .distantPast) > item.updatedAt

            if item.deleted {
                if !localWins, let index = localIndex {
                    data[keyPath: path].remove(at: index)
                }
                data.tombstones.removeAll { $0.collection == collection && $0.id == item.id }
                continue
            }

            guard var payload = item.payload else { continue }
            payload.updatedAt = item.updatedAt

            // A local delete that happened after this version still stands.
            if let tomb = data.tombstones.first(where: { $0.collection == collection && $0.id == item.id }),
               tomb.deletedAt > item.updatedAt {
                continue
            }

            if let index = localIndex {
                if !localWins {
                    data[keyPath: path][index] = payload
                }
            } else {
                data[keyPath: path].append(payload)
            }
        }
    }

    private func mergeTravel(_ items: [SyncItem<TravelEntry>], data: inout AppData) {
        guard !items.isEmpty else { return }
        let dirty = Set(data.dirty.ids(.travelTimes))

        for item in items {
            let localStamp = data.travel[item.id]?.updatedAt
            let localWins = dirty.contains(item.id) && (localStamp ?? .distantPast) > item.updatedAt

            if item.deleted {
                if !localWins { data.travel.removeValue(forKey: item.id) }
                data.tombstones.removeAll { $0.collection == .travelTimes && $0.id == item.id }
                continue
            }

            guard var entry = item.payload else { continue }
            entry.updatedAt = item.updatedAt
            if !localWins {
                data.travel[item.id] = entry
            }
        }
    }
}
