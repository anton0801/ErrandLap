//
//  RunBuilderView.swift
//  ErrandRun
//
//  The calculation, line by line, with the order explained and always movable.
//

import SwiftUI

struct RunBuilderView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var instance: WindowInstance
    var openRunMode: () -> Void

    @State private var manualOrder: [UUID]?
    @State private var reordering = false
    @State private var showWhy = false
    @State private var consequence: String?
    @State private var lastGoodOrder: [UUID]?
    @State private var startError: String?

    private var automaticPlan: RoutePlan {
        store.planner.plan(for: instance)
    }

    private var result: (plan: RoutePlan, failure: SimFailure?) {
        if let manualOrder {
            return store.planner.plan(order: manualOrder, for: instance)
        }
        return (automaticPlan, nil)
    }

    var body: some View {
        let current = result
        return ERScreen(sparkSeed: 17) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Run Builder", onBack: { dismiss() })

                    windowCard(plan: current.plan)
                    calculationCard(plan: current.plan)

                    if let consequence {
                        ERCard(tone: .active) {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "What That Costs")
                                Text(consequence)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Put It Back") {
                                    withAnimation(.erRebuild) {
                                        manualOrder = lastGoodOrder
                                        self.consequence = nil
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }

                    if current.plan.stops.isEmpty {
                        EREmptyState(title: "Nothing Fits This Window",
                                     message: emptyReason(plan: current.plan),
                                     primaryTitle: "Back to Today",
                                     primaryAction: { dismiss() })
                    } else {
                        routeSection(plan: current.plan)
                    }

                    didNotFitSection(plan: current.plan)

                    if !current.plan.stops.isEmpty {
                        VStack(spacing: 10) {
                            Button("Start the Run") { start(plan: current.plan) }
                                .buttonStyle(FireButtonStyle())
                            if manualOrder != nil {
                                Button("Rebuild Automatically") {
                                    withAnimation(.erRebuild) {
                                        manualOrder = nil
                                        consequence = nil
                                        reordering = false
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }

                    if let startError {
                        Text(startError)
                            .font(.erCaption)
                            .foregroundStyle(ER.scarlet)
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .sheet(isPresented: $showWhy) {
            WhyThisOrderView(lines: store.planner.orderExplanation(for: current.plan))
        }
    }

    // MARK: Sections

    private func windowCard(plan: RoutePlan) -> some View {
        ERCard(tone: .active) {
            VStack(alignment: .leading, spacing: 12) {
                ERSectionHeader(text: "Window", trailing: ERTime.dayLabel(instance.day))
                HStack(alignment: .bottom) {
                    ERBigNumber(value: "\(plan.usedMinutes)", caption: "of \(plan.windowMinutes) minutes used")
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(instance.timeText)
                            .font(.erHours)
                            .foregroundStyle(ER.charcoal)
                        Text(instance.window.travelMode.title)
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.6))
                    }
                }
                ERKeyValueRow(key: "From", value: store.data.name(for: instance.window.from).capitalized, mono: false)
                ERKeyValueRow(key: "Must be at", value: "\(store.data.name(for: instance.window.to).capitalized) by \(ERTime.time(instance.end))", mono: false)
                ERKeyValueRow(key: "Buffer between stops", value: "\(store.data.settings.buffer) min")
            }
        }
    }

    private func calculationCard(plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "The Calculation")
            ERCard(index: 1) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(plan.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 9) {
                            DiamondShape()
                                .fill(.fire)
                                .frame(width: 7, height: 7)
                                .padding(.top, 7)
                            Text(line)
                                .font(.erBody)
                                .foregroundStyle(ER.charcoal)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Button("Why This Order") { showWhy = true }
                        .buttonStyle(GhostButtonStyle())
                        .padding(.top, 4)
                }
            }
        }
    }

    private func routeSection(plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ERSectionHeader(text: reordering ? "Move by Hand" : "The Route", trailing: plan.stops.count == 1 ? "1 stop" : "\(plan.stops.count) stops")
                Button(reordering ? "Done" : "Reorder") {
                    withAnimation(.erRebuild) {
                        reordering.toggle()
                        if reordering, manualOrder == nil {
                            manualOrder = plan.stops.map(\.id)
                            lastGoodOrder = manualOrder
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.erSection)
                .foregroundStyle(ER.scarlet)
            }

            if reordering {
                VStack(spacing: 10) {
                    ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, stop in
                        ERCard(index: index, tone: .idle) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(index + 1). \(stop.place.name)")
                                        .font(.erBodyBold)
                                        .foregroundStyle(ER.charcoal)
                                    Text("\(ERTime.time(stop.startInside))–\(ERTime.time(stop.leave)) · \(stop.errand.title)")
                                        .font(.erHoursSmall)
                                        .foregroundStyle(ER.charcoal.opacity(0.65))
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 4)
                                ERIconButton(systemName: "arrow.up") { move(stop.id, by: -1, plan: plan) }
                                ERIconButton(systemName: "arrow.down") { move(stop.id, by: 1, plan: plan) }
                            }
                        }
                    }
                }
            } else {
                RouteRibbon(stops: plan.stops,
                            mode: instance.window.travelMode,
                            currentID: plan.stops.first?.id)
            }
        }
    }

    @ViewBuilder
    private func didNotFitSection(plan: RoutePlan) -> some View {
        if !plan.didNotFit.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ERSectionHeader(text: "Did Not Fit", trailing: "\(plan.didNotFit.count)")
                ForEach(Array(plan.didNotFit.enumerated()), id: \.element.id) { index, missed in
                    VStack(alignment: .leading, spacing: 8) {
                        MissedCard(missed: missed, index: index)
                        Button("Force It Into the Route") {
                            withAnimation(.erRebuild) { force(missed, plan: plan) }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }
        }
        if !plan.noPlace.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "No Place Yet", trailing: "\(plan.noPlace.count)")
                ERCard(tone: .waiting) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(plan.noPlace) { errand in
                            Text("• \(errand.title)")
                                .font(.erBody)
                                .foregroundStyle(ER.charcoal)
                        }
                        Text("Opening hours and travel time live on the place. Until one is set, these cannot be planned.")
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func emptyReason(plan: RoutePlan) -> String {
        if let first = plan.didNotFit.first {
            return first.reason
        }
        if store.data.errands.filter({ $0.state == .open }).isEmpty {
            return "There are no open errands left."
        }
        return "Nothing open right now fits between \(ERTime.time(instance.start)) and \(ERTime.time(instance.end))."
    }

    // MARK: Actions

    private func move(_ id: UUID, by offset: Int, plan: RoutePlan) {
        var order = manualOrder ?? plan.stops.map(\.id)
        guard let index = order.firstIndex(of: id) else { return }
        let target = index + offset
        guard target >= 0, target < order.count else { return }
        lastGoodOrder = order
        order.swapAt(index, target)

        let outcome = store.planner.plan(order: order, for: instance)
        withAnimation(.erRebuild) {
            manualOrder = order
            consequence = outcome.failure.map { failure in
                let name = store.data.place(store.data.errand(failure.errandID)?.placeID)?.name
                    ?? store.data.errand(failure.errandID)?.title ?? "That stop"
                return "\(name): \(failure.reason)"
            }
        }
    }

    private func force(_ missed: MissedErrand, plan: RoutePlan) {
        var order = manualOrder ?? plan.stops.map(\.id)
        lastGoodOrder = order
        order.append(missed.id)
        let outcome = store.planner.plan(order: order, for: instance)
        manualOrder = order
        consequence = outcome.failure.map { failure in
            let name = store.data.place(store.data.errand(failure.errandID)?.placeID)?.name
                ?? store.data.errand(failure.errandID)?.title ?? "That stop"
            return "\(name): \(failure.reason)"
        } ?? "\(missed.place?.name ?? missed.errand.title) now fits after all the others."
    }

    private func start(plan: RoutePlan) {
        guard !plan.stops.isEmpty else {
            startError = "There is nothing to run yet."
            return
        }
        if let existing = store.activeRun, existing.state == .running {
            store.finish(run: existing, state: .abandoned)
        }
        _ = store.startRun(from: plan)
        openRunMode()
    }
}

// MARK: - Why this order

struct WhyThisOrderView: View {
    @Environment(\.dismiss) private var dismiss
    var lines: [String]

    var body: some View {
        ERScreen(sparkSeed: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Why This Order", onBack: { dismiss() })

                    if lines.isEmpty {
                        EREmptyState(title: "Nothing in the Route",
                                     message: "Once something fits, this explains why it goes where it goes.")
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            ERCard(index: index, tone: index == lines.count - 1 ? .active : .idle) {
                                Text(line)
                                    .font(index == lines.count - 1 ? .erBodyBold : .erBody)
                                    .foregroundStyle(ER.charcoal)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .erAppear(index)
                        }
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
    }
}
