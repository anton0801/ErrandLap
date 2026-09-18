//
//  ErrandsView.swift
//  ErrandRun
//

import SwiftUI

enum ErrandsRoute: Hashable {
    case detail(UUID)
    case delegation
}

struct ErrandsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var path: [ErrandsRoute] = []
    @State private var creating = false
    @State private var search = ""
    @State private var openSections: Set<ErrandSection> = [.open, .scheduled, .waiting, .blocked]

    private func errands(in section: ErrandSection) -> [Errand] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.data.errands
            .filter { store.derived.sections[$0.id] == section }
            .filter { query.isEmpty || $0.title.lowercased().contains(query) }
            .sorted { lhs, rhs in
                if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var delegatable: Int {
        store.data.errands.filter { $0.canBeDelegated && $0.state == .open }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ERScreen(sparkSeed: 2) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            ERScreenTitle(text: "Errands")
                            ERIconButton(systemName: "plus", filled: true) { creating = true }
                        }

                        if store.data.errands.isEmpty {
                            EREmptyState(
                                title: "Nothing to Run",
                                message: "Add an errand and the app will work out when you can actually do it.",
                                primaryTitle: "Add Errand",
                                primaryAction: { creating = true }
                            )
                        } else {
                            ERTextField(placeholder: "Search errands", text: $search)

                            if delegatable > 0 {
                                ERNavRow(title: "Someone Else's Hands",
                                         detail: "\(delegatable) errand\(delegatable == 1 ? "" : "s") marked as delegable.") {
                                    path.append(.delegation)
                                }
                            }

                            ForEach(ErrandSection.allCases) { section in
                                sectionView(section)
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
            .navigationDestination(for: ErrandsRoute.self) { route in
                switch route {
                case .detail(let id):
                    ErrandDetailView(errandID: id)
                        .navigationBarHidden(true)
                case .delegation:
                    DelegationView()
                        .navigationBarHidden(true)
                }
            }
        }
        .sheet(isPresented: $creating) {
            ErrandEditorView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: ErrandSection) -> some View {
        let items = errands(in: section)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.erCard) {
                        if openSections.contains(section) { openSections.remove(section) } else { openSections.insert(section) }
                    }
                } label: {
                    HStack {
                        ERSectionHeader(text: section.rawValue, trailing: "\(items.count)")
                        Image(systemName: openSections.contains(section) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(ER.scarlet)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if openSections.contains(section) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, errand in
                        ErrandRow(errand: errand,
                                  placeName: store.data.place(errand.placeID)?.name,
                                  section: section,
                                  index: index,
                                  note: note(for: errand, section: section)) {
                            path.append(.detail(errand.id))
                        }
                        .erAppear(index)
                    }
                }
            }
        }
    }

    private func note(for errand: Errand, section: ErrandSection) -> String? {
        switch section {
        case .blocked:
            return store.planner.blockingReason(errand)
        case .waiting:
            guard let instance = store.planner.nextFittingInstance(for: errand, after: nil, days: 14) else { return nil }
            return "Waiting for \(ERTime.dayPhrase(instance.day)), \(instance.timeText)."
        case .open:
            if errand.placeID == nil { return "No place yet, so it cannot be planned." }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Detail

struct ErrandDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var errandID: UUID

    @State private var editing = false
    @State private var showDropConfirm = false

    private var errand: Errand? { store.data.errand(errandID) }

    var body: some View {
        ERScreen(sparkSeed: 11) {
            ScrollView {
                if let errand {
                    VStack(alignment: .leading, spacing: 20) {
                        ERNavBar(title: errand.title, onBack: { dismiss() },
                                 trailing: AnyView(ERIconButton(systemName: "pencil") { editing = true }))

                        statusCard(errand)
                        factsCard(errand)

                        if let reason = store.planner.blockingReason(errand) {
                            ERCard(index: 1, tone: .blocked) {
                                Text(reason)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        deadlineCard(errand)
                        documentsCard(errand)
                        shoppingCard(errand)
                        delegationCard(errand)

                        if !errand.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "Notes")
                                ERCard(index: 4) {
                                    Text(errand.notes)
                                        .font(.erBody)
                                        .foregroundStyle(ER.charcoal)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        actions(errand)

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ERNavBar(title: "Errand", onBack: { dismiss() })
                        EREmptyState(title: "Errand Deleted",
                                     message: "It is no longer in your list.",
                                     primaryTitle: "Go Back",
                                     primaryAction: { dismiss() })
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let errand {
                ErrandEditorView(existing: errand)
                    .environmentObject(store)
            }
        }
        .alert("Drop this errand?", isPresented: $showDropConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Drop it", role: .destructive) {
                if let errand { store.setState(.dropped, for: errand) }
            }
        } message: {
            Text("It stays in the list under Dropped, so you can bring it back.")
        }
    }

    private func statusCard(_ errand: Errand) -> some View {
        let section = store.derived.sections[errand.id] ?? .open
        return ERCard(tone: section.tone, glow: section == .done) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ERTag(text: section.rawValue, color: section.tone.color, filled: section == .done)
                    Spacer(minLength: 0)
                    Text("\(errand.duration) min")
                        .font(.erHours)
                        .foregroundStyle(ER.charcoal)
                }
                if section == .waiting, let instance = store.planner.nextFittingInstance(for: errand, after: nil, days: 21) {
                    Text("Waiting for a window. The next one that fits is \(ERTime.dayPhrase(instance.day)) at \(instance.timeText).")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                } else if section == .waiting {
                    Text("Waiting for a window. Nothing in the next three weeks fits it — it may need its own time, or someone else.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                } else if section == .scheduled {
                    Text("This one is in a route already.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal)
                } else if section == .open, errand.placeID == nil {
                    Text("No place yet. Opening hours and travel time come from the place, so this cannot be planned until you set one.")
                        .font(.erBody)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func factsCard(_ errand: Errand) -> some View {
        ERCard(index: 1) {
            VStack(alignment: .leading, spacing: 9) {
                ERKeyValueRow(key: "Place", value: store.data.place(errand.placeID)?.name ?? "Not set", mono: false)
                if let place = store.data.place(errand.placeID) {
                    ERKeyValueRow(key: "Open today", value: place.hours(on: Date()).shortText)
                    let knowledge = store.planner.queue(for: place.id)
                    ERKeyValueRow(key: "Queue allowance", value: "\(knowledge.allowance) min", mono: true)
                    Text(knowledge.sentence)
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ERKeyValueRow(key: "Category", value: errand.category.title, mono: false)
                ERKeyValueRow(key: "Priority", value: errand.priority.title, mono: false)
                if let recurrence = errand.recurrence {
                    ERKeyValueRow(key: "Repeats", value: recurrence.intervalTitle, mono: false)
                    ERKeyValueRow(key: "Next due", value: ERTime.shortDate(recurrence.nextDue), mono: false)
                }
            }
        }
    }

    @ViewBuilder
    private func deadlineCard(_ errand: Errand) -> some View {
        if let deadline = errand.deadline {
            let windows = store.planner.windowsBefore(deadline: deadline, for: errand)
            ERCard(index: 2, tone: windows.count <= 1 ? .active : .idle) {
                VStack(alignment: .leading, spacing: 8) {
                    ERSectionHeader(text: "Deadline")
                    Text("\(errand.title) by \(ERTime.fullDate(deadline)).")
                        .font(.erBodyBold)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(windows.isEmpty
                         ? "No windows left where the place is open. Delegate it, or make time for it on purpose."
                         : "\(AppStore.spell(windows.count)) window\(windows.count == 1 ? "" : "s") left where the place is open.")
                        .font(.erBody)
                        .foregroundStyle(windows.isEmpty ? ER.scarlet : ER.charcoal.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    if let first = windows.first {
                        Text("Nearest: \(ERTime.dayLabel(first.day)) at \(first.timeText).")
                            .font(.erCaption)
                            .foregroundStyle(ER.cherry)
                    }
                    Text("Calendar days say nothing when an office works two days a week until lunch.")
                        .font(.erCaption)
                        .italic()
                        .foregroundStyle(ER.charcoal.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func documentsCard(_ errand: Errand) -> some View {
        if errand.requiresDocuments, !errand.documents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "Take With You")
                ERCard(index: 3, tone: .waiting) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(errand.documents, id: \.self) { document in
                            HStack(spacing: 10) {
                                DiamondShape().fill(.fire).frame(width: 10, height: 10)
                                Text(document)
                                    .font(.erBody)
                                    .foregroundStyle(ER.charcoal)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func shoppingCard(_ errand: Errand) -> some View {
        if errand.isShopping {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "Shopping List",
                                trailing: "\(errand.shopping.filter(\.bought).count) of \(errand.shopping.count)")
                if errand.shopping.isEmpty {
                    ERCard {
                        Text("No items yet. Add them in the editor — the list opens on the spot when you get there.")
                            .font(.erBody)
                            .foregroundStyle(ER.charcoal.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ShoppingList(errandID: errand.id)
                }
            }
        }
    }

    @ViewBuilder
    private func delegationCard(_ errand: Errand) -> some View {
        if errand.canBeDelegated {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "Someone Else's Hands")
                ERCard(index: 5, tone: .waiting) {
                    VStack(alignment: .leading, spacing: 10) {
                        ERKeyValueRow(key: "Assigned to",
                                      value: errand.delegation?.assignedTo.isEmpty == false ? errand.delegation!.assignedTo : "Nobody yet",
                                      mono: false)
                        ERKeyValueRow(key: "Status", value: (errand.delegation?.status ?? .notAssigned).title, mono: false)
                        ShareLink(item: DelegationText.build(errand: errand, store: store)) {
                            Text("Share Instructions")
                                .font(.erButton)
                                .textCase(.uppercase)
                                .foregroundStyle(ER.cherry)
                                .frame(maxWidth: .infinity)
                                .frame(height: ERMetric.buttonHeight)
                                .background { BeveledRect().fill(.fire) }
                        }
                        Text("The app sends nothing itself, and the other person does not need it installed.")
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func actions(_ errand: Errand) -> some View {
        VStack(spacing: 10) {
            if errand.state == .open {
                Button("Mark as Done") {
                    store.setState(.done, for: errand)
                }
                .buttonStyle(FireButtonStyle())

                Button("Drop It") { showDropConfirm = true }
                    .buttonStyle(GhostButtonStyle())
            } else {
                Button("Bring It Back") {
                    store.setState(.open, for: errand)
                }
                .buttonStyle(FireButtonStyle())
            }
        }
    }
}

// MARK: - Shopping list

struct ShoppingList: View {
    @EnvironmentObject private var store: AppStore
    var errandID: UUID
    var dark: Bool = false

    private var errand: Errand? { store.data.errand(errandID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let errand {
                ForEach(Array(errand.shopping.enumerated()), id: \.element.id) { index, item in
                    ERCard(index: index, tone: item.bought ? .done : .idle, glow: item.bought, dark: dark) {
                        Button {
                            toggle(item)
                        } label: {
                            HStack(spacing: 10) {
                                DiamondShape()
                                    .fill(item.bought ? AnyShapeStyle(.fire) : AnyShapeStyle((dark ? ER.cream : ER.charcoal).opacity(0.25)))
                                    .frame(width: 14, height: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.erBodyBold)
                                        .foregroundStyle(dark ? ER.cream : ER.charcoal)
                                        .strikethrough(item.bought)
                                    if !item.quantity.isEmpty || !item.note.isEmpty {
                                        Text([item.quantity, item.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.erCaption)
                                            .foregroundStyle((dark ? ER.cream : ER.charcoal).opacity(0.65))
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func toggle(_ item: ShoppingItem) {
        store.mutate { data in
            guard let errandIndex = data.errands.firstIndex(where: { $0.id == errandID }),
                  let itemIndex = data.errands[errandIndex].shopping.firstIndex(where: { $0.id == item.id }) else { return }
            data.errands[errandIndex].shopping[itemIndex].bought.toggle()
        }
    }
}
