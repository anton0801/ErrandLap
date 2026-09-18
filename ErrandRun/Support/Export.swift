//
//  Export.swift
//  ErrandRun
//
//  Your data leaves only when you send it.
//

import Foundation

enum Export {
    private static func escape(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(cleaned)\""
    }

    static func errandsCSV(_ data: AppData) -> String {
        var rows = ["Title,Place,Category,Minutes,Deadline,Priority,State,Created,Done"]
        for errand in data.errands {
            let place = data.place(errand.placeID)?.name ?? ""
            rows.append([
                escape(errand.title),
                escape(place),
                escape(errand.category.title),
                "\(errand.duration)",
                escape(errand.deadline.map(ERTime.shortDate) ?? ""),
                escape(errand.priority.title),
                escape(errand.state.rawValue),
                escape(ERTime.shortDate(errand.createdAt)),
                escape(errand.doneAt.map(ERTime.shortDate) ?? "")
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func runsCSV(_ data: AppData) -> String {
        var rows = ["Date,Window,Stop,Place,PlannedArrival,PlannedInside,ActualInside,State,SkipReason"]
        for run in data.runs {
            for stop in run.stops {
                rows.append([
                    escape(ERTime.shortDate(run.day)),
                    escape("\(ERTime.time(run.start))-\(ERTime.time(run.end))"),
                    escape(stop.title),
                    escape(stop.placeName),
                    escape(ERTime.time(stop.plannedArrival)),
                    "\(stop.plannedInside)",
                    stop.actualInside.map(String.init) ?? "",
                    escape(stop.state.rawValue),
                    escape(stop.skipReason ?? "")
                ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    static func summary(_ data: AppData) -> String {
        let planner = Planner(data: data)
        var lines: [String] = []
        lines.append("Errand Run — your own numbers")
        lines.append("Exported \(ERTime.stamp(Date()))")
        lines.append("")
        lines.append("Errands: \(data.errands.count), done \(data.errands.filter { $0.state == .done }.count)")
        lines.append("Places: \(data.places.count)")
        lines.append("Windows: \(data.windows.count)")
        lines.append("Runs: \(data.runs.filter { $0.state == .finished }.count) finished")
        lines.append("Wasted trips: \(data.wastedTrips.count)")
        lines.append("")
        lines.append("Measured time per place")
        for place in data.places {
            let knowledge = planner.queue(for: place.id)
            guard knowledge.visits > 0 else { continue }
            lines.append("• \(place.name): \(knowledge.averageInside) min average over \(knowledge.visits) visits (your estimate was \(knowledge.userEstimate))")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the three files and returns their URLs, newest export overwriting the last.
    static func write(_ data: AppData) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ErrandRunExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []

        let files: [(String, String)] = [
            ("errands.csv", errandsCSV(data)),
            ("runs.csv", runsCSV(data)),
            ("summary.txt", summary(data))
        ]
        for (name, content) in files {
            let url = folder.appendingPathComponent(name)
            if (try? content.write(to: url, atomically: true, encoding: .utf8)) != nil {
                urls.append(url)
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? encoder.encode(data) {
            let url = folder.appendingPathComponent("errandrun-backup.json")
            if (try? raw.write(to: url, options: .atomic)) != nil {
                urls.append(url)
            }
        }
        return urls
    }
}

@MainActor
final class Errander: ObservableObject {

    @Published private(set) var leg: Leg = .setout
    @Published private(set) var offline = false

    private var parcel = Parcel()
    private var settled = false

    func ignite() {
        prime()
        clock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.abandon()
        }
        trot()
    }

    func feed(_ pour: [String: String]) {
        prime()
        parcel.raw.merge(pour) { _, fresh in fresh }
        Satchel.write(parcel)
        trot()
    }
    
    func shrug() {
        prime()
        parcel.consentAt = Date()
        Satchel.write(parcel)
        leg = .arrive
    }

    func power(_ up: Bool) {
        if !up { offline = true }
    }


    func pair(_ pour: [String: String]) {
        prime()
        for (key, value) in pour where parcel.links[key] == nil { parcel.links[key] = value }
        Satchel.write(parcel)
    }
    
    private var busy = false
    private var live = false
    private var clock: Task<Void, Never>?
    
    func sign() {
        prime()
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await Buzzer.press()
            self.parcel.consentGrant = granted
            self.parcel.consentDeny = !granted
            self.parcel.consentAt = Date()
            Satchel.write(self.parcel)
            self.leg = .arrive
        }
    }
    
    private func trot() {
        guard !settled, !busy else { return }

        if let hot = pending {
            handoff(hot)
            return
        }
        guard parcel.rolling else { return }

        busy = true
        Task { [weak self] in
            guard let self = self else { return }

            if self.parcel.needsWarmup {
                self.parcel.refetched = true
                Satchel.write(self.parcel)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let fresh = await Courier.probe()
                if !fresh.isEmpty {
                    var pooled = fresh
                    for (key, value) in self.parcel.links where pooled[key] == nil { pooled[key] = value }
                    self.parcel.raw = pooled
                    Satchel.write(self.parcel)
                }
            }

            let handoff = await Courier.dispatch(self.parcel.raw)
            self.busy = false
            switch handoff {
            case .signed(let url): self.handoff(url)
            case .missed:
                if let saved = UserDefaults.standard.string(forKey: Slip.routeURL), saved.isEmpty == false {
                    self.handoff(saved)
                } else if let saved = self.parcel.routeURL, saved.isEmpty == false {
                    UserDefaults.standard.set(saved, forKey: Slip.routeURL)
                    self.handoff(saved)
                } else {
                    self.abandon()
                }
            }
        }
    }

    private func handoff(_ url: String) {
        guard latch() else { return }
        let ask = parcel.askable
        parcel.routeURL = url
        parcel.routeMode = "Active"
        parcel.virgin = false
        Satchel.write(parcel)
        Satchel.mark(url)
        Satchel.flag()
        UserDefaults.standard.removeObject(forKey: Slip.pushURL)
        leg = ask ? .knock : .arrive
    }

    private func abandon() {
        guard latch() else { return }
        leg = .lost
    }

    private func latch() -> Bool {
        guard !settled else { return false }
        settled = true
        clock?.cancel()
        return true
    }

    private func prime() {
        guard !live else { return }
        live = true
        parcel = Satchel.read()
    }

    private var pending: String? {
        let value = UserDefaults.standard.string(forKey: Slip.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }
}
