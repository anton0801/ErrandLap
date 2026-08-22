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
