//
//  SetupView.swift
//  ErrandRun
//
//  Initial setup. Cannot be finished without a home point and a travel mode.
//

import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: AppStore
    var isInitial: Bool
    var onClose: (() -> Void)? = nil

    @State private var name = ""
    @State private var home = ""
    @State private var work = ""
    @State private var mode: TravelMode?
    @State private var pace: WalkingPace = .normal
    @State private var buffer = 5
    @State private var saving = false
    @State private var geocodeNote: String?

    private var canSave: Bool {
        !home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mode != nil && !saving
    }

    var body: some View {
        ERScreen(sparkSeed: 5) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if isInitial {
                        ERScreenTitle(text: "Initial Setup")
                        ERNote(text: "Two things are required: where you usually start from, and how you move. Everything else can wait.")
                    } else {
                        ERNavBar(title: "Profile", onBack: { onClose?() })
                    }

                    ERField("Your Display Name", hint: "Only used to address you in this app.") {
                        ERTextField(placeholder: "Anton", text: $name)
                    }

                    ERField("Home Location", hint: "The address you usually leave from and come back to.") {
                        ERTextField(placeholder: "Street, number, city", text: $home)
                    }

                    ERField("Work Location", hint: "Optional. Useful when your free window starts at work.") {
                        ERTextField(placeholder: "Street, number, city", text: $work)
                    }

                    ERField("Default Travel Mode", hint: "Used for new windows and for travel times.") {
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ForEach(TravelMode.allCases) { item in
                                        ERChip(title: item.title, selected: mode == item) {
                                            withAnimation(.erPress) { mode = item }
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 2)
                            }
                            if mode == nil {
                                Text("Pick one to continue.")
                                    .font(.erCaption)
                                    .foregroundStyle(ER.scarlet)
                            }
                        }
                    }

                    if mode == .walking || mode == .mixed {
                        ERField("Walking Pace", hint: "Used when a route has to be estimated rather than measured.") {
                            ERChipRow(items: WalkingPace.allCases, title: { $0.title }, selection: $pace)
                        }
                    }

                    ERField("Buffer Between Stops",
                            hint: "Parking, finding the entrance, the lift. This is what turns a theoretically possible route into a real one.") {
                        ERChipRow(items: [0, 5, 10, 15], title: { "\($0) min" }, selection: $buffer)
                    }

                    if let geocodeNote {
                        ERCard(tone: .waiting) {
                            Text(geocodeNote)
                                .font(.erBody)
                                .foregroundStyle(ER.charcoal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button(isInitial ? "Save Setup" : "Save Changes") { save() }
                        .buttonStyle(FireButtonStyle())
                        .disabled(!canSave)

                    if !isInitial {
                        Button("Cancel") { onClose?() }
                            .buttonStyle(CancelButtonStyle())
                    }

                    Text(AppMode.setupStorageLine)
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        let settings = store.data.settings
        name = settings.displayName
        home = settings.homeAddress
        work = settings.workAddress
        mode = settings.setupComplete ? settings.travelMode : nil
        pace = settings.walkingPace
        buffer = settings.buffer
    }

    private func save() {
        guard let mode else { return }
        saving = true
        let oldHome = store.data.settings.homeAddress
        let oldWork = store.data.settings.workAddress

        store.mutate { data in
            data.settings.displayName = name.trimmingCharacters(in: .whitespaces)
            data.settings.homeAddress = home.trimmingCharacters(in: .whitespaces)
            data.settings.workAddress = work.trimmingCharacters(in: .whitespaces)
            data.settings.travelMode = mode
            data.settings.walkingPace = pace
            data.settings.buffer = buffer
            data.settings.setupComplete = true
            if data.settings.homeAddress != oldHome { data.settings.homeCoordinate = nil }
            if data.settings.workAddress != oldWork { data.settings.workCoordinate = nil }
        }
        store.saveNow()

        // Never blocks saving: the addresses are located in the background.
        Task { await locate() }

        saving = false
        if !isInitial { onClose?() }
    }

    private func locate() async {
        let homeAddress = store.data.settings.homeAddress
        let workAddress = store.data.settings.workAddress

        if !homeAddress.isEmpty, store.data.settings.homeCoordinate == nil {
            do {
                let point = try await TravelService.geocode(homeAddress)
                store.mutate { $0.settings.homeCoordinate = point }
            } catch {
                geocodeNote = "Saved. The home address could not be located: \((error as? TravelError)?.errorDescription ?? "unknown reason") You can still enter travel times by hand."
            }
        }
        if !workAddress.isEmpty, store.data.settings.workCoordinate == nil {
            if let point = try? await TravelService.geocode(workAddress) {
                store.mutate { $0.settings.workCoordinate = point }
            }
        }
    }
}
