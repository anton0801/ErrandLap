//
//  TodayView.swift
//  ErrandRun
//

import SwiftUI

enum TodayRoute: Hashable {
    case builder(String)
    case windows
}

struct TodayView: View {
    @Environment(AppStore.self) private var store

    var selectTab: (ERTab) -> Void
    var openRunMode: () -> Void

    @State private var path: [TodayRoute] = []
    @State private var addingErrand = false
    @State private var addingPlace = false
    @State private var showSettings = false
    @State private var showTravel = false

    private var plan: RoutePlan? { store.derived.todayPlan }
    private var instance: WindowInstance? { plan?.instance }

    var body: some View {
        NavigationStack(path: $path) {
            ERScreen(sparkSeed: 1) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if let run = store.activeRun, run.state == .running {
                            resumeCard(run)
                        }

                        if store.data.errands.filter({ $0.state == .open }).isEmpty {
                            emptyState
                        } else {
                            windowCard
                            countsRow
                            nextStepCard
                            closingSoonCard
                            routeSection
                            didNotFitSection
                            doneThisWeekCard
                        }

                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 10)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .builder:
                    if let instance {
                        RunBuilderView(instance: instance, openRunMode: openRunMode)
                            .navigationBarHidden(true)
                    } else {
                        EmptyBuilderView()
                            .navigationBarHidden(true)
                    }
                case .windows:
                    WindowsView()
                        .navigationBarHidden(true)
                }
            }
        }
        .sheet(isPresented: $addingErrand) { ErrandEditorView().environment(store) }
        .sheet(isPresented: $addingPlace) { PlaceEditorView().environment(store) }
        .sheet(isPresented: $showSettings) { SettingsView().environment(store) }
        .sheet(isPresented: $showTravel) { TravelTimesView().environment(store) }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                ERScreenTitle(text: greeting)
                Text(ERTime.fullDate(Date()))
                    .font(.erCaption)
                    .foregroundStyle(ER.charcoal.opacity(0.6))
            }
            Spacer(minLength: 6)
            ERIconButton(systemName: "gearshape.fill") { showSettings = true }
        }
    }

    private var greeting: String {
        let name = store.data.settings.displayName
        return name.isEmpty ? "Today" : "Today, \(name)"
    }

    private var emptyState: some View {
        EREmptyState(
            title: "Nothing to Run",
            message: "Add an errand and the app will work out when you can actually do it.",
            primaryTitle: "Add Errand",
            primaryAction: { addingErrand = true },
            secondaryTitle: "Add a Place",
            secondaryAction: { addingPlace = true }
        )
    }

    private func resumeCard(_ run: Run) -> some View {
        ERCard(tone: .active) {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "Run in Progress")
                Text("\(run.doneCount) of \(run.stops.count) done. Started at \(ERTime.time(run.start)).")
                    .font(.erBodyBold)
                    .foregroundStyle(ER.charcoal)
                Button("Resume") { openRunMode() }
                    .buttonStyle(FireButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var windowCard: some View {
        if let instance, let plan {
            let slack = max(0, plan.windowMinutes - plan.usedMinutes)
            ERCard(tone: .active) {
                VStack(alignment: .leading, spacing: 12) {
                    ERSectionHeader(text: "Your Window", trailing: ERTime.dayLabel(instance.day))
                    if instance.isRunning {
                        Text("\(instance.window.title.isEmpty ? "This window" : instance.window.title) opened at \(ERTime.time(instance.window.start)). Counted from now, not from then.")
                            .font(.erCaption)
                            .foregroundStyle(ER.cherry)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .bottom, spacing: 14) {
                        ERBigNumber(value: "\(instance.minutes)", caption: instance.isRunning ? "minutes left" : "minutes")
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(instance.timeText)
                                .font(.erHours)
                                .foregroundStyle(ER.charcoal)
                            Text("\(store.data.name(for: instance.window.from)) → \(store.data.name(for: instance.window.to))")
                                .font(.erCaption)
                                .foregroundStyle(ER.charcoal.opacity(0.65))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if !plan.stops.isEmpty {
                        ERKeyValueRow(key: "Leave By", value: ERTime.time(instance.start + slack))
                        ERKeyValueRow(key: "Back at \(store.data.name(for: instance.window.to))", value: ERTime.time(plan.endArrival))
                        ERKeyValueRow(key: "Used", value: "\(plan.usedMinutes) of \(plan.windowMinutes) min")
                    }
                    Button("Windows") { path.append(.windows) }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        } else {
            ERCard(tone: .waiting) {
                VStack(alignment: .leading, spacing: 12) {
                    ERSectionHeader(text: "Waiting for a Window")
                    Text(store.data.windows.isEmpty
                         ? "The app needs to know when you are actually free. A lunch break, Saturday morning — anything real."
                         : "Nothing is open in your windows right now. The next one is \(nextWindowText).")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(store.data.windows.isEmpty ? "Add a Window" : "See Windows") { path.append(.windows) }
                        .buttonStyle(FireButtonStyle())
                }
            }
        }
    }

    private var nextWindowText: String {
        guard let next = store.derived.nextInstance else { return "not set yet" }
        return "\(ERTime.dayLabel(next.day)) at \(next.timeText)"
    }

    @ViewBuilder
    private var countsRow: some View {
        if let plan {
            HStack(alignment: .top, spacing: 12) {
                ERCard(index: 0, tone: .done, glow: !plan.stops.isEmpty) {
                    ERBigNumber(value: "\(plan.stops.count)", caption: "Fits Today")
                }
                ERCard(index: 1, tone: plan.didNotFit.isEmpty ? .idle : .waiting) {
                    ERBigNumber(value: "\(plan.didNotFit.count)", caption: "Did Not Fit", gradient: !plan.didNotFit.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var nextStepCard: some View {
        if let step = store.derived.nextStep {
            ERCard(tone: .active) {
                VStack(alignment: .leading, spacing: 12) {
                    ERSectionHeader(text: "Next Step")
                    Text(step.title)
                        .font(.erScreenTitleSmall)
                        .foregroundStyle(.fire)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.detail)
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    if let title = step.actionTitle, let action = step.action {
                        Button(title) { perform(action) }
                            .buttonStyle(FireButtonStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var closingSoonCard: some View {
        if let plan, let earliest = plan.earliestClosing {
            let minutesLeft = earliest.close - ERTime.minutes(from: Date())
            ERCard(index: 1, tone: minutesLeft < 120 ? .active : .idle) {
                VStack(alignment: .leading, spacing: 8) {
                    ERSectionHeader(text: "Closing Soon")
                    HStack(alignment: .firstTextBaseline) {
                        Text(earliest.place.name)
                            .font(.erCardTitle)
                            .foregroundStyle(ER.charcoal)
                        Spacer(minLength: 6)
                        Text(ERTime.time(earliest.close))
                            .font(.erHours)
                            .foregroundStyle(minutesLeft < 120 ? ER.scarlet : ER.charcoal)
                    }
                    if minutesLeft > 0 {
                        Text("\(ERTime.duration(minutesLeft)) left, travel not counted.")
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.65))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var routeSection: some View {
        if let plan, !plan.stops.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ERSectionHeader(text: "The Route", trailing: plan.stops.count == 1 ? "1 stop" : "\(plan.stops.count) stops")
                RouteRibbon(stops: plan.stops,
                            mode: plan.instance.window.travelMode,
                            currentID: plan.stops.first?.id) { _ in
                    path.append(.builder(plan.instance.id))
                }
                Button("Open the Route") { path.append(.builder(plan.instance.id)) }
                    .buttonStyle(FireButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var didNotFitSection: some View {
        if let plan, !plan.didNotFit.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ERSectionHeader(text: "Did Not Fit", trailing: "\(plan.didNotFit.count)")
                ERNote(text: "Nothing here is lost. Each one is waiting for the next window that actually works.")
                ForEach(Array(plan.didNotFit.enumerated()), id: \.element.id) { index, missed in
                    MissedCard(missed: missed, index: index) {
                        selectTab(.errands)
                    }
                    .erAppear(index)
                }
            }
        }
    }

    @ViewBuilder
    private var doneThisWeekCard: some View {
        if store.derived.doneThisWeek > 0 {
            ERCard(tone: .done, glow: true) {
                HStack(alignment: .bottom) {
                    ERBigNumber(value: "\(store.derived.doneThisWeek)", caption: "Done This Week")
                    Spacer(minLength: 0)
                    SparkField(seed: 21, count: 5)
                        .frame(width: 90, height: 60)
                }
            }
        }
    }

    private func perform(_ action: NextStepAction) {
        switch action {
        case .addErrand: addingErrand = true
        case .addPlace: addingPlace = true
        case .addWindow: path.append(.windows)
        case .assignPlaces: selectTab(.errands)
        case .fixTravelTime: showTravel = true
        case .openBuilder:
            if let instance { path.append(.builder(instance.id)) }
        case .resumeRun: openRunMode()
        }
    }
}

struct EmptyBuilderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ERScreen {
            VStack(alignment: .leading, spacing: 16) {
                ERNavBar(title: "Run Builder", onBack: { dismiss() })
                EREmptyState(title: "No Window to Build In",
                             message: "Add a free window first — the route is built inside it, not around it.",
                             primaryTitle: "Go Back",
                             primaryAction: { dismiss() })
                Spacer()
            }
            .padding(.horizontal, ERMetric.screenPadding)
            .padding(.top, 14)
        }
    }
}
