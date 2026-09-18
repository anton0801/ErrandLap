//
//  RightNowView.swift
//  ErrandRun
//
//  "I have twenty minutes. Right now. What can I actually do?"
//
//  The rest of the app plans against windows the user set up in advance. This is
//  the unplanned case: standing in the street with a gap that was not on any
//  schedule. It builds a throwaway window from the clock to now-plus-N, runs it
//  through the same engine as everything else, and answers in the same sentences.
//
//  Nothing is saved unless the user starts the run.
//

import SwiftUI

struct RightNowView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var openRunMode: () -> Void

    private static let choices = [15, 30, 45, 60, 90]

    @State private var minutes = 30
    @State private var from: Endpoint = .home
    @State private var mode: TravelMode?
    @State private var startedRun = false

    private var travelMode: TravelMode { mode ?? store.data.settings.travelMode }

    /// A window that exists only while this screen is open.
    private var instance: WindowInstance {
        var window = FreeWindow()
        window.title = "Right Now"
        window.isRecurring = false
        window.date = Date()
        window.start = ERTime.minutes(from: Date())
        window.end = min(24 * 60 - 1, window.start + minutes)
        window.from = from
        window.to = from
        window.travelMode = travelMode
        return WindowInstance(window: window, day: Date(), startFrom: nil)
    }

    private var plan: RoutePlan { store.planner.plan(for: instance) }

    var body: some View {
        ERScreen(sparkSeed: 44) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Right Now", onBack: { dismiss() })

                    header

                    ERField("How Long Have You Got?", hint: "From this minute. The clock is already running.") {
                        ERChipRow(items: Self.choices, title: { "\($0) min" }, selection: $minutes)
                    }

                    ERField("Starting From") {
                        ERChipRow(items: startPoints, title: { label(for: $0) }, selection: $from)
                    }

                    ERField("Getting There") {
                        ERChipRow(items: TravelMode.allCases,
                                  title: { $0.title },
                                  selection: Binding(
                                    get: { travelMode },
                                    set: { mode = $0 }
                                  ))
                    }

                    answer

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .animation(.erCard, value: minutes)
        .animation(.erCard, value: from)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            SparkField(seed: 45, count: 7)
                .frame(height: 54)
            Text(ERTime.time(ERTime.minutes(from: Date())) + " — " + ERTime.time(instance.end))
                .font(.erHours)
                .foregroundStyle(ER.charcoal.opacity(0.7))
        }
    }

    @ViewBuilder
    private var answer: some View {
        let plan = self.plan
        let fits = plan.stops

        if store.data.errands.filter({ $0.state == .open }).isEmpty {
            ERCard(tone: .idle) {
                VStack(alignment: .leading, spacing: 8) {
                    ERSectionHeader(text: "Nothing to Run")
                    Text("There are no open errands to fit into this gap.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal.opacity(0.8))
                }
            }
        } else if fits.isEmpty {
            ERCard(tone: .waiting) {
                VStack(alignment: .leading, spacing: 10) {
                    ERSectionHeader(text: "Nothing Fits")
                    Text(nothingFitsReason(plan))
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A longer gap, or a different starting point, may change that.")
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.65))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ERCard(tone: .done, glow: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        ERSectionHeader(text: "You Can Do", trailing: "\(fits.count)")
                        Text(headline(for: fits))
                            .font(.erCardTitle)
                            .foregroundStyle(ER.charcoal)
                            .fixedSize(horizontal: false, vertical: true)
                        ERKeyValueRow(key: "Back by", value: ERTime.time(plan.endArrival + plan.returnTravel))
                        ERKeyValueRow(key: "Uses", value: "\(plan.usedMinutes) of \(minutes) min")
                    }
                }

                ForEach(Array(fits.enumerated()), id: \.element.id) { index, stop in
                    ERCard(index: index + 1) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stop.errand.title)
                                .font(.erBodyBold)
                                .foregroundStyle(ER.charcoal)
                            Text(stop.place.name)
                                .font(.erCaption)
                                .foregroundStyle(ER.charcoal.opacity(0.7))
                            ERKeyValueRow(key: "Leave at", value: ERTime.time(stop.depart))
                            ERKeyValueRow(key: "Inside", value: "\(stop.inside) min")
                            if let close = stop.close {
                                ERKeyValueRow(key: "Closes", value: ERTime.time(close))
                            }
                        }
                    }
                }

                if !plan.lines.isEmpty {
                    ERCard(tone: .idle) {
                        VStack(alignment: .leading, spacing: 6) {
                            ERSectionHeader(text: "The Arithmetic")
                            ForEach(Array(plan.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.erCaption)
                                    .foregroundStyle(ER.charcoal.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Button("Start This Run") { start(plan) }
                    .buttonStyle(FireButtonStyle())

                ERNote(text: "Nothing is saved until you start it. This gap is not added to your windows.")
            }
        }
    }

    // MARK: Helpers

    private var startPoints: [Endpoint] {
        var points: [Endpoint] = [.home]
        if !store.data.settings.workAddress.isEmpty { points.append(.work) }
        return points
    }

    private func label(for endpoint: Endpoint) -> String {
        switch endpoint {
        case .home: return "Home"
        case .work: return "Work"
        case .place(let id): return store.data.place(id)?.name ?? "A place"
        case .custom(let name): return name
        }
    }

    private func headline(for stops: [StopPlan]) -> String {
        if stops.count == 1, let only = stops.first {
            return "\(only.errand.title) at \(only.place.name)."
        }
        return stops.map(\.errand.title).joined(separator: ", ") + "."
    }

    private func nothingFitsReason(_ plan: RoutePlan) -> String {
        if let first = plan.didNotFit.first {
            return first.reason
        }
        if !plan.noPlace.isEmpty {
            return "The open errands have no place attached yet, so there is nothing to travel to."
        }
        return "Nothing on the list fits into \(minutes) minutes from here."
    }

    private func start(_ plan: RoutePlan) {
        let run = store.startRun(from: plan)
        _ = run
        startedRun = true
        dismiss()
        // Give the sheet a moment to close before the dark screen takes over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            openRunMode()
        }
    }
}
