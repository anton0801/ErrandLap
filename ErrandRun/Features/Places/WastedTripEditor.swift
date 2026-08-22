//
//  WastedTripEditor.swift
//  ErrandRun
//
//  You went, and it was for nothing. Recording why saves the next trip.
//

import SwiftUI

struct WastedTripEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var place: Place
    var errandID: UUID? = nil
    var onSaved: (() -> Void)? = nil

    @State private var reason: WastedReason = .closedUnexpectedly
    @State private var missing = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var saving = false

    var body: some View {
        ERScreen(sparkSeed: 13) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Wasted Trip", onBack: { dismiss() })

                    ERNote(text: "Wasted trips are the most expensive thing in errands. Writing down why turns one into a warning on the place.")

                    ERField("Place") {
                        ERCard {
                            HStack {
                                Text(place.name)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                Spacer(minLength: 6)
                                Text(place.hours(on: date).shortText)
                                    .font(.erHours)
                                    .foregroundStyle(ER.charcoal.opacity(0.7))
                            }
                        }
                    }

                    ERField("Date") {
                        DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(ER.scarlet)
                    }

                    ERField("Reason") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(WastedReason.allCases) { item in
                                Button {
                                    withAnimation(.erPress) { reason = item }
                                } label: {
                                    HStack(spacing: 10) {
                                        DiamondShape()
                                            .fill(reason == item ? AnyShapeStyle(.fire) : AnyShapeStyle(ER.charcoal.opacity(0.2)))
                                            .frame(width: 12, height: 12)
                                        Text(item.title)
                                            .font(.erBody)
                                            .foregroundStyle(ER.charcoal)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ERField("What Was Missing", hint: "The document, the person, the working terminal.") {
                        ERTextField(placeholder: "Passport copy", text: $missing)
                    }

                    ERField("Notes") {
                        ERTextEditor(placeholder: "The door said the hours changed from the first of the month.", text: $notes)
                    }

                    Button("Save Wasted Trip") { save() }
                        .buttonStyle(FireButtonStyle())
                        .disabled(saving)

                    Button("Cancel") { dismiss() }
                        .buttonStyle(CancelButtonStyle())

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        store.add(wastedTrip: WastedTrip(placeID: place.id,
                                         errandID: errandID,
                                         date: date,
                                         reason: reason,
                                         missing: missing.trimmingCharacters(in: .whitespaces),
                                         notes: notes.trimmingCharacters(in: .whitespaces)))
        store.saveNow()
        saving = false
        onSaved?()
        dismiss()
    }
}
