//
//  DelegationView.swift
//  ErrandRun
//
//  Errands that do not need your hands.
//

import SwiftUI

enum DelegationText {
    static func build(errand: Errand, store: AppStore) -> String {
        var lines: [String] = []
        lines.append(errand.title)
        if let place = store.data.place(errand.placeID) {
            lines.append("Where: \(place.name)")
            if !place.address.isEmpty { lines.append("Address: \(place.address)") }
            lines.append("Open today: \(place.hours(on: Date()).text)")
            let week = place.hours.summary
            if !week.isEmpty { lines.append("Hours: \(week)") }
            if !place.notes.isEmpty { lines.append("Note: \(place.notes)") }
        }
        if errand.requiresDocuments, !errand.documents.isEmpty {
            lines.append("Take: " + errand.documents.joined(separator: ", "))
        }
        if let instructions = errand.delegation?.instructions, !instructions.isEmpty {
            lines.append("Instructions: \(instructions)")
        }
        if errand.isShopping, !errand.shopping.isEmpty {
            lines.append("List:")
            for item in errand.shopping where !item.bought {
                let quantity = item.quantity.isEmpty ? "" : " — \(item.quantity)"
                let note = item.note.isEmpty ? "" : " (\(item.note))"
                lines.append("• \(item.name)\(quantity)\(note)")
            }
        }
        if let deadline = errand.deadline {
            lines.append("Needed by: \(ERTime.fullDate(deadline))")
        }
        return lines.joined(separator: "\n")
    }
}

struct DelegationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingID: UUID?

    private var errands: [Errand] {
        store.data.errands
            .filter { $0.canBeDelegated && $0.state == .open }
            .sorted { ($0.delegation?.assignedTo ?? "") < ($1.delegation?.assignedTo ?? "") }
    }

    var body: some View {
        ERScreen(sparkSeed: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Someone Else", onBack: { dismiss() })

                    ERNote(text: "The app sends nothing by itself. It writes down what to buy, where to go, what to take and until when — you send it however you like.")

                    if errands.isEmpty {
                        EREmptyState(title: "Nothing to Hand Over",
                                     message: "Mark an errand as something someone else could do, and it turns up here with instructions ready to share.")
                    } else {
                        ForEach(Array(errands.enumerated()), id: \.element.id) { index, errand in
                            card(errand: errand, index: index)
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

    private func card(errand: Errand, index: Int) -> some View {
        let delegation = errand.delegation ?? Delegation()
        return ERCard(index: index, tone: delegation.status == .doneByThem ? .done : .waiting,
                      glow: delegation.status == .doneByThem) {
            VStack(alignment: .leading, spacing: 12) {
                Text(errand.title)
                    .font(.erCardTitle)
                    .foregroundStyle(ER.charcoal)
                if let place = store.data.place(errand.placeID) {
                    Text("\(place.name) · \(place.hours(on: Date()).shortText)")
                        .font(.erHoursSmall)
                        .foregroundStyle(ER.charcoal.opacity(0.7))
                }

                ERTextField(placeholder: "Assigned to", text: Binding(
                    get: { store.data.errand(errand.id)?.delegation?.assignedTo ?? "" },
                    set: { newValue in update(errand) { $0.assignedTo = newValue } }
                ))

                ERTextEditor(placeholder: "Instructions", text: Binding(
                    get: { store.data.errand(errand.id)?.delegation?.instructions ?? "" },
                    set: { newValue in update(errand) { $0.instructions = newValue } }
                ), minHeight: 70)

                if errand.requiresDocuments, !errand.documents.isEmpty {
                    Text("Documents needed: " + errand.documents.joined(separator: ", "))
                        .font(.erCaption)
                        .foregroundStyle(ER.cherry)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ERSectionHeader(text: "Status")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DelegationStatus.allCases) { status in
                                ERChip(title: status.title, selected: delegation.status == status) {
                                    update(errand) { $0.status = status }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 2)
                    }
                }

                ShareLink(item: DelegationText.build(errand: errand, store: store)) {
                    Text("Share Instructions")
                        .font(.erButton)
                        .textCase(.uppercase)
                        .foregroundStyle(ER.cherry)
                        .frame(maxWidth: .infinity)
                        .frame(height: ERMetric.buttonHeight)
                        .background { BeveledRect().fill(.fire) }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    if delegation.status == .notAssigned || delegation.status == .assigned {
                        update(errand) { $0.status = .shared }
                    }
                })

                if delegation.status == .doneByThem {
                    Button("Mark the Errand Done") {
                        store.setState(.done, for: errand)
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private func update(_ errand: Errand, _ change: (inout Delegation) -> Void) {
        store.mutate { data in
            guard let index = data.errands.firstIndex(where: { $0.id == errand.id }) else { return }
            var delegation = data.errands[index].delegation ?? Delegation()
            change(&delegation)
            data.errands[index].delegation = delegation
        }
    }
}
