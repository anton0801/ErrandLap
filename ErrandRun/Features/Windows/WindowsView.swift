//
//  WindowsView.swift
//  ErrandRun
//
//  A window has a start and an end in real places: you leave work, you must be
//  at the school. That is what makes a route end where it has to.
//

import SwiftUI

struct EndpointPicker: View {
    @EnvironmentObject private var store: AppStore
    @Binding var endpoint: Endpoint
    var label: String

    @State private var customText = ""

    private var isCustom: Bool {
        if case .custom = endpoint { return true }
        return false
    }

    var body: some View {
        ERField(label) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ERChip(title: "Home", selected: endpoint == .home) { endpoint = .home }
                        if !store.data.settings.workAddress.isEmpty {
                            ERChip(title: "Work", selected: endpoint == .work) { endpoint = .work }
                        }
                        ForEach(store.data.places) { place in
                            ERChip(title: place.name, selected: endpoint == .place(place.id)) {
                                endpoint = .place(place.id)
                            }
                        }
                        ERChip(title: "Somewhere else", selected: isCustom) {
                            endpoint = .custom(customText.isEmpty ? "the meeting point" : customText)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 2)
                }
                if isCustom {
                    ERTextField(placeholder: "The school", text: Binding(
                        get: { customText },
                        set: { newValue in
                            customText = newValue
                            endpoint = .custom(newValue.isEmpty ? "the meeting point" : newValue)
                        }
                    ))
                    Text("A point without an address has no measured travel time — enter it by hand in Travel Times, or the route will not count the last leg.")
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if case .custom(let value) = endpoint { customText = value }
        }
    }
}

struct WindowsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: FreeWindow?
    @State private var creating = false

    var body: some View {
        ERScreen(sparkSeed: 15) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Windows", onBack: { dismiss() },
                             trailing: AnyView(ERIconButton(systemName: "plus", filled: true) { creating = true }))

                    ERNote(text: "A window is the time you can actually spend on errands, with a start and an end in real places.")

                    if store.data.windows.isEmpty {
                        EREmptyState(title: "No Windows Yet",
                                     message: "A lunch break on weekdays, Saturday morning. Set it once and the app will keep planning inside it.",
                                     primaryTitle: "Add a Window",
                                     primaryAction: { creating = true })
                    } else {
                        ForEach(Array(store.data.windows.enumerated()), id: \.element.id) { index, window in
                            Button { editing = window } label: {
                                ERCard(index: index, tone: window.isEnabled ? .idle : .dropped) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(window.title.isEmpty ? window.daysText : window.title)
                                                .font(.erCardTitle)
                                                .foregroundStyle(ER.charcoal)
                                            Spacer(minLength: 6)
                                            Text(window.timeText)
                                                .font(.erHours)
                                                .foregroundStyle(ER.charcoal)
                                        }
                                        Text("\(window.daysText) · \(ERTime.duration(window.lengthMinutes))")
                                            .font(.erCaption)
                                            .foregroundStyle(ER.charcoal.opacity(0.65))
                                        HStack(spacing: 6) {
                                            ERTag(text: store.data.name(for: window.from), color: ER.cherry)
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 10, weight: .black))
                                                .foregroundStyle(ER.scarlet)
                                            ERTag(text: store.data.name(for: window.to), color: ER.cherry)
                                            ERTag(text: window.travelMode.title, color: ER.charcoal.opacity(0.6))
                                            Spacer(minLength: 0)
                                        }
                                        if !window.isEnabled {
                                            ERTag(text: "Off", color: ER.charcoal.opacity(0.5))
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .erAppear(index)
                        }
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .sheet(isPresented: $creating) {
            WindowEditorView().environmentObject(store)
        }
        .sheet(item: $editing) { window in
            WindowEditorView(existing: window).environmentObject(store)
        }
    }
}

struct WindowEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var existing: FreeWindow?

    @State private var window = FreeWindow()
    @State private var saving = false
    @State private var showDeleteConfirm = false
    @State private var error: String?

    private var isNew: Bool { existing == nil }

    private var valid: Bool {
        window.end > window.start && (!window.isRecurring || !window.weekdays.isEmpty)
    }

    var body: some View {
        ERScreen(sparkSeed: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ERNavBar(title: isNew ? "New Window" : "Edit Window", onBack: { dismiss() })

                    ERField("Name", hint: "Optional. “Lunch break”, “Saturday morning”.") {
                        ERTextField(placeholder: "Lunch break", text: $window.title)
                    }

                    ERField("Repeats") {
                        VStack(alignment: .leading, spacing: 10) {
                            ERCard {
                                ERToggleRow(title: "Every week",
                                            subtitle: "Set it once instead of typing it in again every Monday.",
                                            isOn: $window.isRecurring)
                            }
                            if window.isRecurring {
                                dayPicker
                            } else {
                                DatePicker("", selection: Binding(
                                    get: { window.date ?? Date() },
                                    set: { window.date = $0 }
                                ), displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .tint(ER.scarlet)
                            }
                        }
                    }

                    ERField("Time") {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                ERSectionHeader(text: "Starts")
                                ERTimeField(minutes: $window.start)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                ERSectionHeader(text: "Ends")
                                ERTimeField(minutes: $window.end)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    if window.end > window.start {
                        Text("\(ERTime.minutesWord(window.end - window.start)) of real time.")
                            .font(.erCaption)
                            .foregroundStyle(ER.cherry)
                    } else {
                        Text("The end has to come after the start.")
                            .font(.erCaption)
                            .foregroundStyle(ER.scarlet)
                    }

                    EndpointPicker(endpoint: $window.from, label: "Starting Point")
                    EndpointPicker(endpoint: $window.to, label: "Ending Point")

                    ERField("Travel Mode") {
                        ERChipRow(items: TravelMode.allCases, title: { $0.title }, selection: $window.travelMode)
                    }

                    ERCard {
                        ERToggleRow(title: "Window is on", isOn: $window.isEnabled)
                    }

                    if let error {
                        Text(error)
                            .font(.erCaption)
                            .foregroundStyle(ER.scarlet)
                    }

                    Button(isNew ? "Add Window" : "Save Changes") { save() }
                        .buttonStyle(FireButtonStyle())
                        .disabled(!valid || saving)

                    if !isNew {
                        Button("Delete Window") { showDeleteConfirm = true }
                            .buttonStyle(CancelButtonStyle())
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if let existing {
                window = existing
            } else {
                window.travelMode = store.data.settings.travelMode
            }
        }
        .alert("Delete this window?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let existing {
                    store.delete(window: existing)
                    dismiss()
                }
            }
        } message: {
            Text("Errands planned into it go back to waiting.")
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(ERTime.weekOrder, id: \.self) { weekday in
                let selected = window.weekdays.contains(weekday)
                Button {
                    withAnimation(.erPress) {
                        if selected {
                            window.weekdays.removeAll { $0 == weekday }
                        } else {
                            window.weekdays.append(weekday)
                        }
                    }
                } label: {
                    Text(String(ERTime.weekdayName(weekday, short: true).prefix(2)))
                        .font(.erCaption)
                        .foregroundStyle(selected ? ER.cherry : ER.charcoal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            if selected {
                                BeveledRect(radius: 9, cap: 8).fill(.fire)
                            } else {
                                BeveledRect(radius: 9, cap: 8).stroke(ER.charcoal, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        guard !saving, valid else { return }
        saving = true
        window.title = window.title.trimmingCharacters(in: .whitespaces)
        if !window.isRecurring, window.date == nil { window.date = Date() }
        store.upsert(window)
        store.saveNow()
        saving = false
        dismiss()
    }
}
