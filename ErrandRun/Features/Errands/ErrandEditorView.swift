//
//  ErrandEditorView.swift
//  ErrandRun
//

import SwiftUI

struct ErrandEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var existing: Errand?
    var onSaved: ((Errand) -> Void)? = nil

    @State private var errand = Errand()
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var repeats = false
    @State private var recurrence = Recurrence()
    @State private var documentDraft = ""
    @State private var itemDraft = ""
    @State private var pickingPlace = false
    @State private var showDeleteConfirm = false
    @State private var saving = false
    @State private var titleError: String?

    private var isNew: Bool { existing == nil }
    private var trimmedTitle: String { errand.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedTitle.isEmpty && errand.duration > 0 && !saving }

    /// Errands that may be depended on: not itself, and nothing that depends on this one.
    private var dependencyCandidates: [Errand] {
        store.data.errands.filter { candidate in
            candidate.id != errand.id
                && candidate.state == .open
                && !dependsTransitively(candidate, on: errand.id)
        }
    }

    private func dependsTransitively(_ candidate: Errand, on target: UUID) -> Bool {
        var seen: Set<UUID> = []
        var current: Errand? = candidate
        while let node = current, let next = node.dependsOn, !seen.contains(next) {
            if next == target { return true }
            seen.insert(next)
            current = store.data.errand(next)
        }
        return false
    }

    var body: some View {
        ERScreen(sparkSeed: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ERNavBar(title: isNew ? "New Errand" : "Edit Errand", onBack: { dismiss() })

                    ERField("Errand Title") {
                        VStack(alignment: .leading, spacing: 6) {
                            ERTextField(placeholder: "Collect the certificate", text: $errand.title)
                            if let titleError {
                                Text(titleError)
                                    .font(.erCaption)
                                    .foregroundStyle(ER.scarlet)
                            }
                        }
                    }

                    placeField
                    categoryField

                    ERField("How Long It Takes",
                            hint: "This is how long the thing itself takes. Travel and queue are counted separately, because you control one and not the other.") {
                        VStack(alignment: .leading, spacing: 10) {
                            ERChipRow(items: [5, 10, 15, 20, 30, 45, 60, 90],
                                      title: { "\($0) min" },
                                      selection: $errand.duration)
                            ERStepperRow(title: "Exactly", value: $errand.duration, range: 1...480, step: 5)
                        }
                    }

                    deadlineField
                    priorityField
                    documentsField
                    dependencyField

                    if errand.isShopping { shoppingField }

                    delegationField
                    recurrenceField

                    ERField("Notes") {
                        ERTextEditor(placeholder: "The second window is the one that takes cards.", text: $errand.notes)
                    }

                    Button(isNew ? "Add Errand" : "Save Changes") { save() }
                        .buttonStyle(FireButtonStyle())
                        .disabled(!canSave)

                    if !isNew {
                        Button("Delete Errand") { showDeleteConfirm = true }
                            .buttonStyle(CancelButtonStyle())
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear(perform: prefill)
        .sheet(isPresented: $pickingPlace) {
            PlacePicker(selection: $errand.placeID)
                .environment(store)
        }
        .alert("Delete this errand?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let existing {
                    store.delete(errand: existing)
                    dismiss()
                }
            }
        } message: {
            Text("Anything that depended on it becomes unblocked.")
        }
    }

    // MARK: Fields

    private var placeField: some View {
        ERField("Place", hint: "Opening hours and travel time come from the place. Without one the errand cannot be planned.") {
            Button {
                pickingPlace = true
            } label: {
                ERCard(tone: errand.placeID == nil ? .waiting : .idle) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.data.place(errand.placeID)?.name ?? "Choose a place")
                                .font(.erBodyBold)
                                .foregroundStyle(errand.placeID == nil ? ER.scarlet : ER.charcoal)
                            if let place = store.data.place(errand.placeID) {
                                Text(place.hours(on: Date()).text)
                                    .font(.erHoursSmall)
                                    .foregroundStyle(ER.charcoal.opacity(0.65))
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text("You can add it later — saving is never blocked.")
                                    .font(.erCaption)
                                    .foregroundStyle(ER.charcoal.opacity(0.6))
                            }
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(ER.scarlet)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var categoryField: some View {
        ERField("Category") {
            ERChipRow(items: Category.allCases, title: { $0.title }, selection: $errand.category)
        }
    }

    private var deadlineField: some View {
        ERField("Deadline", hint: "Urgency is measured in windows left, not in days left.") {
            VStack(alignment: .leading, spacing: 10) {
                ERCard {
                    ERToggleRow(title: "Has a deadline", isOn: $hasDeadline)
                }
                if hasDeadline {
                    DatePicker("", selection: $deadline, in: Date()..., displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(ER.scarlet)
                    if let place = store.data.place(errand.placeID) {
                        let windows = store.planner.windowsBefore(deadline: deadline, for: previewErrand())
                        Text(windows.isEmpty
                             ? "No window before that date fits this errand at \(place.name)."
                             : "\(AppStore.spell(windows.count)) window\(windows.count == 1 ? "" : "s") left where \(place.name) is open.")
                            .font(.erCaption)
                            .foregroundStyle(windows.isEmpty ? ER.scarlet : ER.cherry)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var priorityField: some View {
        ERField("Priority", hint: "Priority breaks ties. It never beats opening hours.") {
            ERChipRow(items: Priority.allCases, title: { $0.title }, selection: $errand.priority)
        }
    }

    private var documentsField: some View {
        ERField("Requires Documents", hint: "Shown on the live route when you get there, so nothing is left on the table at home.") {
            VStack(alignment: .leading, spacing: 10) {
                ERCard {
                    ERToggleRow(title: "Something has to be taken", isOn: $errand.requiresDocuments)
                }
                if errand.requiresDocuments {
                    HStack(spacing: 8) {
                        ERTextField(placeholder: "What to take", text: $documentDraft)
                        ERIconButton(systemName: "plus", filled: true) { addDocument() }
                    }
                    if !errand.documents.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(errand.documents, id: \.self) { document in
                                HStack(spacing: 10) {
                                    DiamondShape().fill(.fire).frame(width: 10, height: 10)
                                    Text(document)
                                        .font(.erBody)
                                        .foregroundStyle(ER.charcoal)
                                    Spacer(minLength: 6)
                                    Button {
                                        errand.documents.removeAll { $0 == document }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .black))
                                            .foregroundStyle(ER.cherry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var dependencyField: some View {
        ERField("Depends On", hint: "A dependent errand stays out of the route until the first one is done.") {
            VStack(alignment: .leading, spacing: 8) {
                ERChip(title: "Nothing", selected: errand.dependsOn == nil) {
                    withAnimation(.erPress) { errand.dependsOn = nil }
                }
                ForEach(dependencyCandidates) { candidate in
                    ERChip(title: candidate.title, selected: errand.dependsOn == candidate.id) {
                        withAnimation(.erPress) {
                            errand.dependsOn = errand.dependsOn == candidate.id ? nil : candidate.id
                        }
                    }
                }
                if let dependency = store.data.errand(errand.dependsOn) {
                    Text("Blocked until “\(dependency.title)” is done.")
                        .font(.erCaption)
                        .foregroundStyle(ER.cherry)
                }
            }
        }
    }

    private var shoppingField: some View {
        ERField("Shopping List", hint: "Opens right on the spot in the live route. No second app.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ERTextField(placeholder: "What to buy", text: $itemDraft)
                    ERIconButton(systemName: "plus", filled: true) { addItem() }
                }
                ForEach($errand.shopping) { $item in
                    ERCard(tone: item.bought ? .done : .idle, glow: item.bought) {
                        HStack(spacing: 10) {
                            Button {
                                item.bought.toggle()
                            } label: {
                                DiamondShape()
                                    .fill(item.bought ? AnyShapeStyle(.fire) : AnyShapeStyle(ER.charcoal.opacity(0.2)))
                                    .frame(width: 14, height: 14)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                    .strikethrough(item.bought)
                                if !item.quantity.isEmpty || !item.note.isEmpty {
                                    Text([item.quantity, item.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.erCaption)
                                        .foregroundStyle(ER.charcoal.opacity(0.65))
                                }
                            }
                            Spacer(minLength: 6)
                            Button {
                                errand.shopping.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(ER.cherry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var delegationField: some View {
        ERField("Can Be Done By Someone Else") {
            VStack(alignment: .leading, spacing: 10) {
                ERCard {
                    ERToggleRow(title: "Someone else could do this",
                                subtitle: "It gets its own list, with instructions you can share.",
                                isOn: $errand.canBeDelegated)
                }
                if errand.canBeDelegated {
                    ERTextField(placeholder: "Who is doing it", text: Binding(
                        get: { errand.delegation?.assignedTo ?? "" },
                        set: { newValue in
                            var delegation = errand.delegation ?? Delegation()
                            delegation.assignedTo = newValue
                            if delegation.status == .notAssigned, !newValue.isEmpty { delegation.status = .assigned }
                            errand.delegation = delegation
                        }
                    ))
                    ERTextEditor(placeholder: "Instructions: which window, what to say, what to bring back.", text: Binding(
                        get: { errand.delegation?.instructions ?? "" },
                        set: { newValue in
                            var delegation = errand.delegation ?? Delegation()
                            delegation.instructions = newValue
                            errand.delegation = delegation
                        }
                    ), minHeight: 80)
                }
            }
        }
    }

    private var recurrenceField: some View {
        ERField("Repeats", hint: "A repeating errand does not book a date. It waits for a window inside its tolerance.") {
            VStack(alignment: .leading, spacing: 10) {
                ERCard {
                    ERToggleRow(title: "This comes back", isOn: $repeats)
                }
                if repeats {
                    ERChipRow(items: Recurrence.presets,
                              title: { days in Recurrence(intervalDays: days).intervalTitle },
                              selection: $recurrence.intervalDays)
                    VStack(alignment: .leading, spacing: 6) {
                        ERSectionHeader(text: "Next due")
                        DatePicker("", selection: $recurrence.nextDue, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(ER.scarlet)
                    }
                    ERStepperRow(title: "Flexible by", value: $recurrence.flexibleByDays, range: 0...30, step: 1, suffix: "days")
                    Text("This is due in the next \(recurrence.flexibleByDays + 1) day\(recurrence.flexibleByDays == 0 ? "" : "s"), not on a fixed date. It will slot into a window that fits.")
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastDone = recurrence.lastDone {
                        ERKeyValueRow(key: "Last done", value: ERTime.shortDate(lastDone))
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func previewErrand() -> Errand {
        var copy = errand
        copy.deadline = hasDeadline ? deadline : nil
        return copy
    }

    private func addDocument() {
        let value = documentDraft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        errand.documents.append(value)
        documentDraft = ""
    }

    private func addItem() {
        let value = itemDraft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        errand.shopping.append(ShoppingItem(name: value))
        itemDraft = ""
    }

    private func prefill() {
        if let existing {
            errand = existing
            hasDeadline = existing.deadline != nil
            deadline = existing.deadline ?? Date()
            repeats = existing.recurrence != nil
            recurrence = existing.recurrence ?? Recurrence()
        } else {
            errand.duration = 15
            recurrence.nextDue = Date()
        }
    }

    private func save() {
        guard !saving else { return }
        guard !trimmedTitle.isEmpty else {
            titleError = "An errand needs a title."
            return
        }
        saving = true
        titleError = nil
        errand.title = trimmedTitle
        errand.deadline = hasDeadline ? deadline : nil
        errand.recurrence = repeats ? recurrence : nil
        if !errand.requiresDocuments { errand.documents = [] }
        if !errand.canBeDelegated { errand.delegation = nil }
        if !errand.isShopping { errand.shopping = [] }

        let saved = errand
        store.upsert(saved)
        store.saveNow()
        saving = false
        onSaved?(saved)
        dismiss()
    }
}
