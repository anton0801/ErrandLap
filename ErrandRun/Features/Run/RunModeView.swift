//
//  RunModeView.swift
//  ErrandRun
//
//  The dark screen. Used in the street, with one thing on it at a time.
//

import SwiftUI

struct RunModeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var doneSheet: RunStop?
    @State private var skipSheet: RunStop?
    @State private var showRecheck = false
    @State private var extraMinutes = 0
    @State private var learningNote: String?
    @State private var showShopping = false
    @State private var appeared = false

    private var run: Run? { store.activeRun }

    private var currentStop: RunStop? {
        guard let run else { return nil }
        guard let index = run.currentIndex else { return nil }
        return run.stops[index]
    }

    var body: some View {
        ZStack {
            ER.cherry.ignoresSafeArea()
            VStack {
                SparkField(seed: 31, count: 7, bright: true)
                    .frame(height: 46)
                    .offset(y: -48)
                    .opacity(appeared ? 1 : 0)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)

            if let run {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(run)

                        if let stop = currentStop {
                            currentCard(run: run, stop: stop)
                            actionButtons(run: run, stop: stop)
                        } else {
                            finishedCard(run)
                        }

                        if let learningNote {
                            ERCard(tone: .done, glow: true, dark: true) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ERSectionHeader(text: "Updated", dark: true)
                                    Text(learningNote)
                                        .font(.erBodyBold)
                                        .foregroundStyle(ER.cream)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        progressSection(run)

                        if !run.didNotFit.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "Left Out of This Run", dark: true)
                                ERCard(tone: .waiting, dark: true) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(run.didNotFit.enumerated()), id: \.offset) { _, line in
                                            Text("• \(line)")
                                                .font(.erCaption)
                                                .foregroundStyle(ER.cream.opacity(0.8))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        Button("End the Run") {
                            store.finish(run: run, state: run.doneCount > 0 ? .finished : .abandoned)
                            dismiss()
                        }
                        .buttonStyle(GhostButtonStyle(dark: true))

                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 12)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ERNavBar(title: "No Run", dark: true, onBack: { dismiss() })
                    EREmptyState(title: "Nothing Running",
                                 message: "Build a route from Today and start it — this screen is for the road.",
                                 primaryTitle: "Close",
                                 primaryAction: { dismiss() },
                                 dark: true)
                    Spacer()
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(.erDarken) { appeared = true } }
        .sheet(item: $doneSheet) { stop in
            DoneSheet(stop: stop) { minutes in
                complete(stop: stop, minutes: minutes)
            }
            .environment(store)
        }
        .sheet(item: $skipSheet) { stop in
            SkipSheet(stop: stop) { reason, logWaste in
                skip(stop: stop, reason: reason, logWaste: logWaste)
            }
            .environment(store)
        }
        .sheet(isPresented: $showRecheck) {
            if let run {
                RecheckSheet(run: run, extra: extraMinutes) { action in
                    handle(action: action, run: run)
                }
                .environment(store)
            }
        }
        .sheet(isPresented: $showShopping) {
            if let stop = currentStop {
                ShoppingSheet(errandID: stop.errandID)
                    .environment(store)
            }
        }
    }

    // MARK: Pieces

    private func header(_ run: Run) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                ERScreenTitle(text: "Run Mode", small: true)
                Text("\(ERTime.time(run.start))–\(ERTime.time(run.end)) · back to \(store.data.name(for: run.to))")
                    .font(.erCaption)
                    .foregroundStyle(ER.cream.opacity(0.7))
            }
            Spacer(minLength: 6)
            ERIconButton(systemName: "chevron.down", dark: true) { dismiss() }
        }
    }

    private func currentCard(run: Run, stop: RunStop) -> some View {
        let nowMinutes = ERTime.minutes(from: Date())
        let behind = nowMinutes - stop.plannedArrival
        return ERCard(tone: .active, dark: true) {
            VStack(alignment: .leading, spacing: 14) {
                ERSectionHeader(text: stop.state == .arrived ? "You Are Here" : "Next Stop", dark: true)

                Text(stop.placeName)
                    .font(.system(size: 30, weight: .black).italic())
                    .foregroundStyle(.fire)
                    .fixedSize(horizontal: false, vertical: true)

                Text(stop.title)
                    .font(.erBody)
                    .foregroundStyle(ER.cream)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .bottom, spacing: 16) {
                    if let close = stop.closeTime {
                        let left = max(0, close - nowMinutes)
                        VStack(alignment: .leading, spacing: -2) {
                            Text(ERTime.duration(left))
                                .font(.erNumber)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundStyle(left < 45 ? ER.scarlet : ER.gold)
                            Text("until it closes at \(ERTime.time(close))")
                                .font(.erCaption)
                                .foregroundStyle(ER.cream.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Planned \(ERTime.time(stop.plannedArrival))")
                            .font(.erHoursSmall)
                            .foregroundStyle(ER.cream.opacity(0.75))
                        if let lastEntry = stop.lastEntry {
                            Text("Last entry \(ERTime.time(lastEntry))")
                                .font(.erHoursSmall)
                                .foregroundStyle(ER.scarlet)
                        }
                    }
                }

                if behind > 4 {
                    Text("You are \(behind) minutes behind the plan.")
                        .font(.erBodyBold)
                        .foregroundStyle(ER.scarlet)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !stop.documents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ERSectionHeader(text: "Take With You", dark: true)
                        ForEach(stop.documents, id: \.self) { document in
                            HStack(spacing: 9) {
                                DiamondShape().fill(.fire).frame(width: 9, height: 9)
                                Text(document)
                                    .font(.erBody)
                                    .foregroundStyle(ER.cream)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                if let errand = store.data.errand(stop.errandID), errand.isShopping, !errand.shopping.isEmpty {
                    Button("Open the Shopping List (\(errand.shopping.filter { !$0.bought }.count) left)") {
                        showShopping = true
                    }
                    .buttonStyle(GhostButtonStyle(dark: true))
                }

                if let placeID = stop.placeID {
                    Text(store.planner.queue(for: placeID).sentence)
                        .font(.erCaption)
                        .foregroundStyle(ER.cream.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func actionButtons(run: Run, stop: RunStop) -> some View {
        VStack(spacing: 10) {
            if stop.state == .pending {
                Button("Arrived") { arrive(stop: stop) }
                    .buttonStyle(FireButtonStyle())
            } else {
                Button("Done") { doneSheet = stop }
                    .buttonStyle(FireButtonStyle())
            }

            HStack(spacing: 10) {
                Button("Skipped") { skipSheet = stop }
                    .buttonStyle(GhostButtonStyle(dark: true))
                Button("Running Late") {
                    extraMinutes = 0
                    showRecheck = true
                }
                .buttonStyle(GhostButtonStyle(dark: true))
            }

            HStack(spacing: 8) {
                Text("Add time")
                    .font(.erSection)
                    .foregroundStyle(ER.cream.opacity(0.7))
                ForEach([5, 10, 15], id: \.self) { minutes in
                    ERChip(title: "+\(minutes)", selected: false, dark: true) {
                        extraMinutes = minutes
                        showRecheck = true
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func finishedCard(_ run: Run) -> some View {
        ERCard(tone: .done, glow: true, dark: true) {
            VStack(alignment: .leading, spacing: 14) {
                ERSectionHeader(text: "Run Finished", dark: true)
                HStack(alignment: .bottom, spacing: 16) {
                    ERBigNumber(value: "\(run.doneCount)", caption: "done", dark: true)
                    if run.skippedCount > 0 {
                        ERBigNumber(value: "\(run.skippedCount)", caption: "skipped", dark: true, gradient: false)
                    }
                    Spacer(minLength: 0)
                }
                Text("Your measured times are saved. The next route will be built on them.")
                    .font(.erBody)
                    .foregroundStyle(ER.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Close the Run") {
                    store.finish(run: run, state: .finished)
                    dismiss()
                }
                .buttonStyle(FireButtonStyle())
            }
        }
    }

    private func progressSection(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ERSectionHeader(text: "The Whole Route", trailing: "\(run.doneCount)/\(run.stops.count)", dark: true)
            VStack(spacing: 0) {
                ForEach(Array(run.stops.enumerated()).reversed(), id: \.element.id) { index, stop in
                    RunStopCard(stop: stop,
                                index: index,
                                isCurrent: stop.id == currentStop?.id,
                                mode: run.travelMode)
                        .padding(.leading, CGFloat(index) * 11)
                        .scaleEffect(stop.id == currentStop?.id ? 1.15 : 1)
                        .padding(.vertical, stop.id == currentStop?.id ? 10 : 0)
                        .zIndex(stop.id == currentStop?.id ? 2 : 1)

                    if index > 0 {
                        RouteConnector(dark: true)
                            .padding(.leading, CGFloat(index - 1) * 11)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func arrive(stop: RunStop) {
        guard var run else { return }
        guard let index = run.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        run.stops[index].state = .arrived
        run.stops[index].arrivedAt = Date()
        store.update(run: run)
    }

    private func complete(stop: RunStop, minutes: Int) {
        guard var run else { return }
        guard let index = run.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        run.stops[index].state = .done
        run.stops[index].actualInside = minutes
        store.update(run: run)

        if let errand = store.data.errand(stop.errandID) {
            store.setState(.done, for: errand)
            if let placeID = stop.placeID {
                store.logVisit(placeID: placeID,
                               errandID: errand.id,
                               estimated: stop.plannedInside,
                               actual: minutes,
                               taskMinutes: errand.duration)
                learningNote = store.learningNote(for: placeID)
            }
        }

        if store.activeRun?.currentIndex == nil, let finished = store.activeRun {
            store.update(run: finished)
        }
    }

    private func skip(stop: RunStop, reason: String, logWaste: Bool) {
        guard var run else { return }
        guard let index = run.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        run.stops[index].state = .skipped
        run.stops[index].skipReason = reason
        store.update(run: run)

        if logWaste, let placeID = stop.placeID {
            let mapped: WastedReason
            switch reason {
            case WastedReason.closedUnexpectedly.title: mapped = .closedUnexpectedly
            case WastedReason.queueTooLong.title: mapped = .queueTooLong
            case WastedReason.missingDocument.title: mapped = .missingDocument
            case WastedReason.systemDown.title: mapped = .systemDown
            case WastedReason.wrongPerson.title: mapped = .wrongPerson
            case WastedReason.wrongHours.title: mapped = .wrongHours
            default: mapped = .other
            }
            store.add(wastedTrip: WastedTrip(placeID: placeID, errandID: stop.errandID, reason: mapped))
        }
    }

    private func handle(action: RecheckAction, run: Run) {
        var updated = run
        switch action {
        case .keepGoing:
            break
        case .drop(let stopID):
            if let index = updated.stops.firstIndex(where: { $0.id == stopID }) {
                updated.stops[index].state = .skipped
                updated.stops[index].skipReason = "Dropped — would not have made it in time"
            }
        case .reorder(let stopID):
            guard let from = updated.stops.firstIndex(where: { $0.id == stopID }),
                  let firstPending = updated.stops.firstIndex(where: { $0.state == .pending }) else { break }
            let moved = updated.stops.remove(at: from)
            updated.stops.insert(moved, at: min(firstPending, updated.stops.count))
        }
        updated.lateMinutes = max(updated.lateMinutes, extraMinutes)
        store.update(run: updated)
    }
}

// MARK: - Run stop card

struct RunStopCard: View {
    var stop: RunStop
    var index: Int
    var isCurrent: Bool
    var mode: TravelMode

    private var tone: ERStatusTone {
        switch stop.state {
        case .done: return .done
        case .skipped: return .dropped
        case .arrived, .pending: return isCurrent ? .active : .idle
        }
    }

    var body: some View {
        ERCard(index: index, tone: tone, glow: stop.state == .done, dark: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ERTime.time(stop.plannedArrival))
                        .font(.erHours)
                        .foregroundStyle(stop.state == .done ? ER.gold : ER.cream)
                    Text(stop.placeName)
                        .font(.erCardTitle)
                        .foregroundStyle(ER.cream)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                Text(stop.title)
                    .font(.erCaption)
                    .foregroundStyle(ER.cream.opacity(0.75))
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ERTag(text: "\(stop.plannedTravel) min \(mode.noun)", color: ER.gold)
                    if let actual = stop.actualInside {
                        ERTag(text: "took \(actual) min", color: ER.gold, filled: true)
                    } else {
                        ERTag(text: "\(stop.plannedInside) min planned", color: ER.gold)
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

// MARK: - Done sheet

struct DoneSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var stop: RunStop
    var onSave: (Int) -> Void

    @State private var minutes = 15

    var body: some View {
        ERScreen(dark: true, sparkSeed: 22) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "How Long Inside?", dark: true, onBack: { dismiss() })

                    ERNote(text: "The measured number, not the hoped-for one. This is what makes the next plan honest.", dark: true)

                    ERCard(dark: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            ERKeyValueRow(key: "Planned", value: "\(stop.plannedInside) min", dark: true)
                            if let arrivedAt = stop.arrivedAt {
                                ERKeyValueRow(key: "Since you arrived",
                                              value: "\(max(1, Int(Date().timeIntervalSince(arrivedAt) / 60))) min",
                                              dark: true)
                            }
                            ERStepperRow(title: "Actually took", value: $minutes, range: 1...480, step: 5)
                                .environment(\.colorScheme, .dark)
                        }
                    }

                    ERChipRow(items: [5, 10, 15, 20, 30, 45, 60, 90],
                              title: { "\($0) min" },
                              selection: $minutes,
                              dark: true)

                    Button("Save and Move On") {
                        onSave(minutes)
                        dismiss()
                    }
                    .buttonStyle(FireButtonStyle())

                    Button("Cancel") { dismiss() }
                        .buttonStyle(CancelButtonStyle())

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let arrivedAt = stop.arrivedAt {
                minutes = max(1, Int(Date().timeIntervalSince(arrivedAt) / 60))
            } else {
                minutes = stop.plannedInside
            }
        }
    }
}

// MARK: - Skip sheet

struct SkipSheet: View {
    @Environment(\.dismiss) private var dismiss

    var stop: RunStop
    var onSkip: (String, Bool) -> Void

    @State private var reason: WastedReason = .closedUnexpectedly
    @State private var logWaste = true

    var body: some View {
        ERScreen(dark: true, sparkSeed: 23) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Skipped", dark: true, onBack: { dismiss() })

                    Text(stop.placeName)
                        .font(.erCardTitle)
                        .foregroundStyle(ER.cream)

                    ERField("Why", dark: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(WastedReason.allCases) { item in
                                Button {
                                    reason = item
                                } label: {
                                    HStack(spacing: 10) {
                                        DiamondShape()
                                            .fill(reason == item ? AnyShapeStyle(.fire) : AnyShapeStyle(ER.cream.opacity(0.25)))
                                            .frame(width: 12, height: 12)
                                        Text(item.title)
                                            .font(.erBody)
                                            .foregroundStyle(ER.cream)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ERCard(dark: true) {
                        ERToggleRow(title: "Log it as a wasted trip",
                                    subtitle: "It turns into a warning on the place next time.",
                                    isOn: $logWaste,
                                    dark: true)
                    }

                    Button("Skip This Stop") {
                        onSkip(reason.title, logWaste)
                        dismiss()
                    }
                    .buttonStyle(FireButtonStyle())

                    Button("Cancel") { dismiss() }
                        .buttonStyle(CancelButtonStyle())

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Recheck sheet

enum RecheckAction {
    case keepGoing
    case drop(UUID)
    case reorder(UUID)
}

struct RecheckSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var run: Run
    var extra: Int
    var onAction: (RecheckAction) -> Void

    private var behind: Int {
        guard let index = run.currentIndex else { return extra }
        return max(0, ERTime.minutes(from: Date()) - run.stops[index].plannedArrival) + extra
    }

    private var pending: [RunStop] {
        run.stops.filter { $0.state == .pending || $0.state == .arrived }
    }

    private var simulation: Simulation {
        let start = ERTime.minutes(from: Date()) + extra
        let from: Endpoint
        if let arrived = run.stops.last(where: { $0.state == .arrived || $0.state == .done }), let placeID = arrived.placeID {
            from = .place(placeID)
        } else {
            from = run.from
        }
        let remaining = pending.filter { stop in
            guard let arrived = run.stops.first(where: { $0.state == .arrived }) else { return true }
            return stop.id != arrived.id
        }
        let context = SimContext(day: run.day,
                                 startMinutes: start,
                                 endMinutes: run.end,
                                 from: from,
                                 to: run.to,
                                 mode: run.travelMode)
        return store.planner.simulate(remaining.map(\.errandID), in: context)
    }

    var body: some View {
        let simulation = self.simulation
        return ERScreen(dark: true, sparkSeed: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Recalculated", dark: true, onBack: { dismiss() })

                    ERCard(tone: .active, dark: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(behind > 0 ? "You are \(behind) minutes behind." : "Recalculated from the clock, not from the plan.")
                                .font(.erCardTitle)
                                .foregroundStyle(ER.cream)
                                .fixedSize(horizontal: false, vertical: true)
                            if let failure = simulation.failure,
                               let errand = store.data.errand(failure.errandID) {
                                Text("\(store.data.place(errand.placeID)?.name ?? errand.title): \(failure.reason)")
                                    .font(.erBody)
                                    .foregroundStyle(ER.cream.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("Everything still fits. Nothing has to be dropped.")
                                    .font(.erBody)
                                    .foregroundStyle(ER.cream.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !simulation.stops.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Still Fits", dark: true)
                            ForEach(Array(simulation.stops.enumerated()), id: \.element.id) { index, stop in
                                ERCard(index: index, dark: true) {
                                    ERKeyValueRow(key: stop.place.name,
                                                  value: "\(ERTime.time(stop.startInside))–\(ERTime.time(stop.leave))",
                                                  dark: true)
                                }
                            }
                        }
                    }

                    if let failure = simulation.failure,
                       let stop = run.stops.first(where: { $0.errandID == failure.errandID }) {
                        VStack(spacing: 10) {
                            Button("Go There First") {
                                onAction(.reorder(stop.id))
                                dismiss()
                            }
                            .buttonStyle(FireButtonStyle())

                            Button("Drop \(stop.placeName)") {
                                onAction(.drop(stop.id))
                                dismiss()
                            }
                            .buttonStyle(GhostButtonStyle(dark: true))

                            Button("Keep Going") {
                                onAction(.keepGoing)
                                dismiss()
                            }
                            .buttonStyle(CancelButtonStyle())
                        }
                    } else {
                        Button("Keep Going") {
                            onAction(.keepGoing)
                            dismiss()
                        }
                        .buttonStyle(FireButtonStyle())
                    }

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shopping sheet

struct ShoppingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var errandID: UUID

    private var errand: Errand? { store.data.errand(errandID) }

    private var otherShoppingErrands: [Errand] {
        store.data.errands.filter { $0.id != errandID && $0.isShopping && $0.state == .open }
    }

    var body: some View {
        ERScreen(dark: true, sparkSeed: 25) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Shopping", dark: true, onBack: { dismiss() })

                    if let errand {
                        ERSectionHeader(text: errand.title,
                                        trailing: "\(errand.shopping.filter(\.bought).count)/\(errand.shopping.count)",
                                        dark: true)
                        ShoppingList(errandID: errandID, dark: true)

                        let unbought = errand.shopping.filter { !$0.bought }
                        if !unbought.isEmpty, !otherShoppingErrands.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "Not Here?", dark: true)
                                Text("Move what you did not find into another shopping errand.")
                                    .font(.erCaption)
                                    .foregroundStyle(ER.cream.opacity(0.75))
                                ForEach(otherShoppingErrands) { other in
                                    Button("Move \(unbought.count) item\(unbought.count == 1 ? "" : "s") to “\(other.title)”") {
                                        move(items: unbought, to: other)
                                    }
                                    .buttonStyle(GhostButtonStyle(dark: true))
                                }
                            }
                        }
                    }

                    Button("Close") { dismiss() }
                        .buttonStyle(FireButtonStyle())

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func move(items: [ShoppingItem], to other: Errand) {
        store.mutate { data in
            guard let sourceIndex = data.errands.firstIndex(where: { $0.id == errandID }),
                  let targetIndex = data.errands.firstIndex(where: { $0.id == other.id }) else { return }
            let ids = Set(items.map(\.id))
            data.errands[sourceIndex].shopping.removeAll { ids.contains($0.id) }
            data.errands[targetIndex].shopping.append(contentsOf: items)
        }
        dismiss()
    }
}
