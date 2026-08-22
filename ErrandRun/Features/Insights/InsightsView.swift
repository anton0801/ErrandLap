//
//  InsightsView.swift
//  ErrandRun
//
//  Your own numbers, never anyone else's.
//

import SwiftUI

struct InsightsView: View {
    @Environment(AppStore.self) private var store

    private var finishedRuns: [Run] {
        store.data.runs.filter { $0.state == .finished }
    }

    private var hasEnough: Bool { finishedRuns.count >= 3 }

    var body: some View {
        ERScreen(sparkSeed: 26) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERScreenTitle(text: "Insights")

                    if !hasEnough {
                        notEnough
                        waitingSection
                    } else {
                        realTimeSection
                        estimatesSection
                        wastedSection
                        waitingSection
                        bestDaySection
                        travellingSection
                        perWindowSection
                    }

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 12)
            }
        }
    }

    // MARK: Not enough

    private var notEnough: some View {
        EREmptyState(
            title: "More Runs Needed",
            message: "Complete at least three runs to see your own numbers. \(finishedRuns.count) of 3 so far. Until then, guessing would be someone else's data dressed up as yours."
        )
    }

    // MARK: Sections

    private var realTimeSection: some View {
        let entries = store.data.places
            .map { ($0, store.planner.queue(for: $0.id)) }
            .filter { $0.1.visits > 0 }
            .sorted { $0.1.averageInside > $1.1.averageInside }
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Real Time per Place")
            if entries.isEmpty {
                ERCard {
                    Text("No measured visits yet. Every time you tap Done in a run, the number lands here.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.0.id) { index, entry in
                    ERCard(index: index, tone: .done, glow: entry.1.visits >= 3) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.0.name)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                Spacer(minLength: 6)
                                Text("\(entry.1.averageInside) min")
                                    .font(.erHours)
                                    .foregroundStyle(ER.charcoal)
                            }
                            Text(entry.1.sentence)
                                .font(.erCaption)
                                .foregroundStyle(ER.charcoal.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                            bar(value: Double(entry.1.averageInside), max: Double(entries.first?.1.averageInside ?? 1))
                        }
                    }
                }
            }
        }
    }

    private var estimatesSection: some View {
        let visits = store.data.visits
        let drift = visits.isEmpty ? 0 : visits.map(\.drift).reduce(0, +) / visits.count
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Estimates vs Reality")
            ERCard(tone: drift > 5 ? .waiting : .done, glow: abs(drift) <= 5) {
                VStack(alignment: .leading, spacing: 12) {
                    ERBigNumber(value: drift > 0 ? "+\(drift)" : "\(drift)", caption: "minutes per errand")
                    Text(driftSentence(drift: drift, count: visits.count))
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Almost everyone is wrong in one direction. Seeing which one is the useful part.")
                        .font(.erCaption)
                        .italic()
                        .foregroundStyle(ER.charcoal.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func driftSentence(drift: Int, count: Int) -> String {
        guard count > 0 else { return "No measurements yet." }
        if drift > 0 {
            return "Across \(count) measured visits, things took \(drift) minutes longer than planned. The app now plans with the longer number."
        }
        if drift < 0 {
            return "Across \(count) measured visits, things took \(-drift) minutes less than planned. Your estimates are cautious."
        }
        return "Across \(count) measured visits, plan and reality match."
    }

    private var wastedSection: some View {
        let trips = store.data.wastedTrips
        let grouped = Dictionary(grouping: trips, by: \.reason)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Wasted Trips and Why", trailing: "\(trips.count)")
            if trips.isEmpty {
                ERCard(tone: .done, glow: true) {
                    Text("Not one wasted trip recorded. That is the whole point of the opening hours.")
                        .font(.erBodyBold)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ERCard(tone: .blocked) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(grouped.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.0.title)
                                        .font(.erBody)
                                        .foregroundStyle(ER.charcoal)
                                    Spacer(minLength: 6)
                                    Text("\(entry.1)")
                                        .font(.erHours)
                                        .foregroundStyle(ER.charcoal)
                                }
                                bar(value: Double(entry.1), max: Double(grouped.first?.1 ?? 1))
                            }
                        }
                        Text("\(trips.count) trip\(trips.count == 1 ? "" : "s") for nothing. Each one is a warning on the place now.")
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var waitingSection: some View {
        let waiting = store.data.errands.filter { errand in
            errand.state == .open && store.derived.sections[errand.id] == .waiting
        }
        .sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Errands That Keep Waiting", trailing: "\(waiting.count)")
            if waiting.isEmpty {
                ERCard {
                    Text("Nothing is stuck. Everything open has a window it can land in.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(Array(waiting.prefix(6).enumerated()), id: \.element.id) { index, errand in
                    ERCard(index: index, tone: .waiting) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(errand.title)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                Spacer(minLength: 6)
                                Text("\(ERTime.daysBetween(errand.createdAt, Date())) days")
                                    .font(.erHours)
                                    .foregroundStyle(ER.charcoal.opacity(0.7))
                            }
                            Text(store.data.place(errand.placeID)?.name ?? "No place")
                                .font(.erCaption)
                                .foregroundStyle(ER.charcoal.opacity(0.65))
                        }
                    }
                }
                ERNote(text: "An errand that never lands in a window usually means there is no window for it. Either it needs its own time, or someone else's hands.")
            }
        }
    }

    private var bestDaySection: some View {
        var totals: [Int: Int] = [:]
        for run in finishedRuns {
            totals[ERTime.weekday(run.day), default: 0] += run.doneCount
        }
        let best = totals.max { $0.value < $1.value }
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Best Day of the Week")
            ERCard(tone: .done, glow: best != nil) {
                if let best {
                    VStack(alignment: .leading, spacing: 10) {
                        ERBigNumber(value: ERTime.weekdayName(best.key), caption: "\(best.value) errands finished")
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(ERTime.weekOrder, id: \.self) { weekday in
                                if let count = totals[weekday], count > 0 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ERKeyValueRow(key: ERTime.weekdayName(weekday), value: "\(count)")
                                        bar(value: Double(count), max: Double(best.value))
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Not enough finished runs to say.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal.opacity(0.75))
                }
            }
        }
    }

    private var travellingSection: some View {
        let travel = finishedRuns.flatMap(\.stops).map(\.plannedTravel).reduce(0, +)
        let inside = finishedRuns.flatMap(\.stops).compactMap(\.actualInside).reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Time Spent Travelling")
            ERCard {
                VStack(alignment: .leading, spacing: 12) {
                    ERBigNumber(value: ERTime.duration(travel), caption: "on the road")
                    ERKeyValueRow(key: "Inside places", value: ERTime.duration(inside))
                    if travel + inside > 0 {
                        let share = Int(Double(travel) / Double(travel + inside) * 100)
                        Text("\(share)% of your errand time is getting there.")
                            .font(.erBody)
                            .foregroundStyle(ER.charcoal)
                        bar(value: Double(share), max: 100)
                    }
                }
            }
        }
    }

    private var perWindowSection: some View {
        let done = finishedRuns.map(\.doneCount).reduce(0, +)
        let average = finishedRuns.isEmpty ? 0 : Double(done) / Double(finishedRuns.count)
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "Errands Done per Window")
            ERCard(tone: .done) {
                VStack(alignment: .leading, spacing: 10) {
                    ERBigNumber(value: String(format: "%.1f", average), caption: "per run")
                    Text("Across \(finishedRuns.count) finished run\(finishedRuns.count == 1 ? "" : "s").")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal.opacity(0.8))
                }
            }
        }
    }

    // MARK: Bar

    private func bar(value: Double, max maximum: Double) -> some View {
        GeometryReader { geo in
            let ratio = maximum > 0 ? min(1, value / maximum) : 0
            ZStack(alignment: .leading) {
                ParallelogramShape(radius: 4, cap: 5)
                    .stroke(ER.charcoal.opacity(0.25), lineWidth: 1.5)
                ParallelogramShape(radius: 4, cap: 5)
                    .fill(.fire)
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 12)
    }
}
