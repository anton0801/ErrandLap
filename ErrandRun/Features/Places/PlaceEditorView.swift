//
//  PlaceEditorView.swift
//  ErrandRun
//

import SwiftUI
import PhotosUI

struct PlaceEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var existing: Place?
    var onSaved: ((Place) -> Void)? = nil

    @State private var place = Place()
    @State private var saving = false
    @State private var showDeleteConfirm = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @State private var titleError: String?

    private var isNew: Bool { existing == nil }

    private var trimmedName: String {
        place.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty && !saving }

    var body: some View {
        ERScreen(sparkSeed: 7) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ERNavBar(title: isNew ? "New Place" : "Edit Place", onBack: { dismiss() })

                    ERField("Place Name") {
                        VStack(alignment: .leading, spacing: 6) {
                            ERTextField(placeholder: "Post office near work", text: $place.name)
                            if let titleError {
                                Text(titleError)
                                    .font(.erCaption)
                                    .foregroundStyle(ER.scarlet)
                            }
                        }
                    }

                    ERField("Address", hint: AppMode.addressHint) {
                        ERTextField(placeholder: "Street, number, city", text: $place.address)
                    }

                    ERField("Category") {
                        ERChipRow(items: Category.allCases, title: { $0.title }, selection: $place.category)
                    }

                    ERField("Opening Hours") {
                        HoursEditor(hours: $place.hours)
                    }

                    ERField("Parking Difficulty", hint: "Adds minutes on arrival, on top of your buffer between stops.") {
                        ERChipRow(items: ParkingDifficulty.allCases, title: { $0.title }, selection: $place.parking)
                    }

                    ERField("Queue Estimate",
                            hint: "Your own guess, not a promise from the app. It gets replaced by your measured average once there is data.") {
                        VStack(alignment: .leading, spacing: 10) {
                            ERStepperRow(title: "Usually takes", value: $place.queueEstimate, range: 0...180, step: 5)
                            if let existing {
                                let knowledge = store.planner.queue(for: existing.id)
                                Text(knowledge.sentence)
                                    .font(.erCaption)
                                    .foregroundStyle(knowledge.learned ? ER.cherry : ER.charcoal.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    ERField("Notes", hint: "Which entrance, which window, whose desk. The things you forget every time.") {
                        ERTextEditor(placeholder: "Second floor. Parcels at the third window.", text: $place.notes)
                    }

                    photosSection

                    Button(isNew ? "Add Place" : "Save Changes") { save() }
                        .buttonStyle(FireButtonStyle())
                        .disabled(!canSave)

                    if !isNew {
                        Button("Delete Place") { showDeleteConfirm = true }
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
            if let existing { place = existing }
        }
        .alert("Delete this place?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let existing {
                    store.delete(place: existing)
                    dismiss()
                }
            }
        } message: {
            Text("Errands here keep their titles but lose the place, so they cannot be planned until you set a new one.")
        }
    }

    private var photosSection: some View {
        ERField("Photos", hint: "The entrance, the list of documents on the door, the queue ticket machine.") {
            VStack(alignment: .leading, spacing: 10) {
                if !place.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(place.photos, id: \.self) { name in
                                ZStack(alignment: .topTrailing) {
                                    if let image = UIImage(contentsOfFile: store.photoURL(name).path) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 96, height: 96)
                                            .clipShape(BeveledRect(radius: 10, cap: 10))
                                            .overlay { BeveledRect(radius: 10, cap: 10).stroke(ER.charcoal, lineWidth: 2) }
                                    }
                                    Button {
                                        place.photos.removeAll { $0 == name }
                                        store.deletePhoto(name)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .black))
                                            .foregroundStyle(ER.cream)
                                            .padding(6)
                                            .background(Circle().fill(ER.cherry))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if loadingPhotos {
                    ERLoadingState(text: "Adding photos")
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Text("Add Photos")
                        .font(.erButton)
                        .textCase(.uppercase)
                        .foregroundStyle(ER.charcoal)
                        .frame(maxWidth: .infinity)
                        .frame(height: ERMetric.buttonHeight)
                        .overlay { BeveledRect().stroke(ER.charcoal, lineWidth: 3) }
                }
                .onChange(of: photoItems) { items in
                    guard !items.isEmpty else { return }
                    loadingPhotos = true
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let name = store.savePhoto(data) {
                                place.photos.append(name)
                            }
                        }
                        photoItems = []
                        loadingPhotos = false
                    }
                }
            }
        }
    }

    private func save() {
        guard !saving else { return }
        guard !trimmedName.isEmpty else {
            titleError = "A place needs a name."
            return
        }
        saving = true
        titleError = nil
        place.name = trimmedName
        place.address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)

        let addressChanged = existing?.address != place.address
        if addressChanged { place.coordinate = nil }

        let saved = place
        store.upsert(saved)
        store.saveNow()

        // Locating the address never blocks the save.
        if addressChanged, !saved.address.isEmpty {
            Task {
                if let point = try? await TravelService.geocode(saved.address) {
                    store.mutate { data in
                        if let index = data.places.firstIndex(where: { $0.id == saved.id }) {
                            data.places[index].coordinate = point
                        }
                    }
                }
            }
        }

        saving = false
        onSaved?(saved)
        dismiss()
    }
}
