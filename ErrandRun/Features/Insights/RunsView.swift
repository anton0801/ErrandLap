//
//  RunsView.swift
//  ErrandRun
//
//  Finished routes are kept whole: plan, fact, what slipped.
//

import SwiftUI

struct RunsView: View {
    @Environment(AppStore.self) private var store

    var openRunMode: () -> Void

    @State private var path: [UUID] = []
    @State private var search = ""
    @State private var dayFilter: Int?

    private var runs: [Run] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.data.runs
            .filter { $0.state != .planned }
            .filter { run in
                dayFilter == nil || ERTime.weekday(run.day) == dayFilter
            }
            .filter { run in
                query.isEmpty
                    || run.stops.contains { $0.title.lowercased().contains(query) || $0.placeName.lowercased().contains(query) }
            }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ERScreen(sparkSeed: 19) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ERScreenTitle(text: "Runs")

                        if let active = store.activeRun, active.state == .running {
                            ERCard(tone: .active) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ERSectionHeader(text: "Run in Progress")
                                    Text("\(active.doneCount) of \(active.stops.count) done.")
                                        .font(.erBodyBold)
                                        .foregroundStyle(ER.charcoal)
                                    Button("Resume") { openRunMode() }
                                        .buttonStyle(FireButtonStyle())
                                }
                            }
                        }

                        if store.data.runs.filter({ $0.state != .planned }).isEmpty {
                            EREmptyState(title: "No Runs Yet",
                                         message: "Once you start a route from Today, it is kept here whole: what was planned, what actually happened, and what was skipped.")
                        } else {
                            ERTextField(placeholder: "Search past runs", text: $search)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ERChip(title: "Any day", selected: dayFilter == nil) {
                                        withAnimation(.erPress) { dayFilter = nil }
                                    }
                                    ForEach(ERTime.weekOrder, id: \.self) { weekday in
                                        ERChip(title: ERTime.weekdayName(weekday, short: true), selected: dayFilter == weekday) {
                                            withAnimation(.erPress) { dayFilter = dayFilter == weekday ? nil : weekday }
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 2)
                            }

                            if runs.isEmpty {
                                EREmptyState(title: "Nothing Matches",
                                             message: "No run answers to that filter.",
                                             primaryTitle: "Clear",
                                             primaryAction: { search = ""; dayFilter = nil })
                            } else {
                                ERSectionHeader(text: "Past Runs", trailing: "\(runs.count)")
                                ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                                    Button { path.append(run.id) } label: {
                                        runCard(run: run, index: index)
                                    }
                                    .buttonStyle(.plain)
                                    .erAppear(index)
                                }
                            }
                        }

                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { id in
                RunDetailView(runID: id)
                    .navigationBarHidden(true)
            }
        }
    }

    private func runCard(run: Run, index: Int) -> some View {
        ERCard(index: index, tone: run.state == .finished ? .done : .dropped, glow: run.state == .finished) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ERTime.dayLabel(run.day))
                        .font(.erCardTitle)
                        .foregroundStyle(ER.charcoal)
                    Spacer(minLength: 6)
                    Text("\(ERTime.time(run.start))–\(ERTime.time(run.end))")
                        .font(.erHours)
                        .foregroundStyle(ER.charcoal.opacity(0.75))
                }
                Text(run.stops.map(\.placeName).joined(separator: " → "))
                    .font(.erCaption)
                    .foregroundStyle(ER.charcoal.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ERTag(text: "\(run.doneCount) done", color: ER.gold, filled: run.doneCount > 0)
                    if run.skippedCount > 0 {
                        ERTag(text: "\(run.skippedCount) skipped", color: ER.scarlet)
                    }
                    if run.state == .abandoned {
                        ERTag(text: "Abandoned", color: ER.charcoal.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Detail

struct RunDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var runID: UUID

    @State private var repeated = false

    private var run: Run? { store.data.run(runID) }

    var body: some View {
        ERScreen(sparkSeed: 20) {
            ScrollView {
                if let run {
                    VStack(alignment: .leading, spacing: 20) {
                        ERNavBar(title: ERTime.dayLabel(run.day), onBack: { dismiss() })

                        ERCard(tone: run.state == .finished ? .done : .dropped, glow: run.state == .finished) {
                            VStack(alignment: .leading, spacing: 12) {
                                ERSectionHeader(text: "The Run", trailing: run.state.rawValue.capitalized)
                                HStack(alignment: .bottom, spacing: 18) {
                                    ERBigNumber(value: "\(run.doneCount)", caption: "done")
                                    ERBigNumber(value: "\(run.stops.count)", caption: "planned", gradient: false)
                                    Spacer(minLength: 0)
                                }
                                ERKeyValueRow(key: "Window", value: "\(ERTime.time(run.start))–\(ERTime.time(run.end))")
                                ERKeyValueRow(key: "From", value: store.data.name(for: run.from).capitalized, mono: false)
                                ERKeyValueRow(key: "To", value: store.data.name(for: run.to).capitalized, mono: false)
                                if let startedAt = run.startedAt {
                                    ERKeyValueRow(key: "Started", value: ERTime.stamp(startedAt))
                                }
                                if let finishedAt = run.finishedAt {
                                    ERKeyValueRow(key: "Finished", value: ERTime.stamp(finishedAt))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Plan and Fact")
                            ForEach(Array(run.stops.enumerated()), id: \.element.id) { index, stop in
                                ERCard(index: index,
                                       tone: stop.state == .done ? .done : (stop.state == .skipped ? .dropped : .idle),
                                       glow: stop.state == .done) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(stop.placeName)
                                                .font(.erBodyBold)
                                                .foregroundStyle(ER.charcoal)
                                            Spacer(minLength: 6)
                                            Text(ERTime.time(stop.plannedArrival))
                                                .font(.erHours)
                                                .foregroundStyle(ER.charcoal.opacity(0.7))
                                        }
                                        Text(stop.title)
                                            .font(.erCaption)
                                            .foregroundStyle(ER.charcoal.opacity(0.7))
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: 6) {
                                            ERTag(text: "planned \(stop.plannedInside) min", color: ER.charcoal.opacity(0.6))
                                            if let actual = stop.actualInside {
                                                let drift = actual - stop.plannedInside
                                                ERTag(text: "took \(actual) min", color: drift > 5 ? ER.scarlet : ER.gold, filled: drift <= 5)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        if let reason = stop.skipReason {
                                            Text(reason)
                                                .font(.erCaption)
                                                .foregroundStyle(ER.scarlet)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        if !run.didNotFit.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "Did Not Fit That Day")
                                ERCard(tone: .waiting) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(run.didNotFit.enumerated()), id: \.offset) { _, line in
                                            Text("• \(line)")
                                                .font(.erCaption)
                                                .foregroundStyle(ER.charcoal.opacity(0.8))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        if repeated {
                            ERCard(tone: .done, glow: true) {
                                Text("Copied into your open errands. Today will place them in the first window that fits.")
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Button("Repeat This Run") { repeatRun(run) }
                                .buttonStyle(FireButtonStyle())
                        }

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ERNavBar(title: "Run", onBack: { dismiss() })
                        EREmptyState(title: "Run Not Found",
                                     message: "It is no longer in your history.",
                                     primaryTitle: "Go Back",
                                     primaryAction: { dismiss() })
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)
                }
            }
        }
    }

    private func repeatRun(_ run: Run) {
        store.mutate { data in
            for stop in run.stops {
                let source = data.errand(stop.errandID)
                var copy = Errand()
                copy.title = stop.title
                copy.placeID = stop.placeID
                copy.duration = source?.duration ?? max(5, stop.plannedInside - stop.queueAllowance)
                copy.category = source?.category ?? .other
                copy.requiresDocuments = !stop.documents.isEmpty
                copy.documents = stop.documents
                copy.priority = source?.priority ?? .normal
                data.errands.append(copy)
            }
        }
        store.saveNow()
        withAnimation(.erCard) { repeated = true }
    }
}
