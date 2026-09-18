//
//  PlacesView.swift
//  ErrandRun
//

import SwiftUI

enum PlacesRoute: Hashable {
    case detail(UUID)
    case travelTimes(UUID?)
}

struct PlacesView: View {
    @EnvironmentObject private var store: AppStore

    @State private var path: [PlacesRoute] = []
    @State private var search = ""
    @State private var filter: Category?
    @State private var editing: Place?
    @State private var creating = false

    private var filtered: [Place] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.data.places
            .filter { place in
                (filter == nil || place.category == filter)
                    && (query.isEmpty || place.name.lowercased().contains(query) || place.address.lowercased().contains(query))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ERScreen(sparkSeed: 4) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center) {
                            ERScreenTitle(text: "Places")
                            ERIconButton(systemName: "plus", filled: true) { creating = true }
                        }

                        if store.data.places.isEmpty {
                            EREmptyState(
                                title: "No Places Yet",
                                message: "A place is an address plus opening hours. Without one, an errand has nothing to be planned around.",
                                primaryTitle: "Add a Place",
                                primaryAction: { creating = true }
                            )
                        } else {
                            ERTextField(placeholder: "Search places", text: $search)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ERChip(title: "All", selected: filter == nil) {
                                        withAnimation(.erPress) { filter = nil }
                                    }
                                    ForEach(Category.allCases) { category in
                                        if store.data.places.contains(where: { $0.category == category }) {
                                            ERChip(title: category.title, selected: filter == category) {
                                                withAnimation(.erPress) { filter = filter == category ? nil : category }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 2)
                            }

                            ERNavRow(title: "Travel Times",
                                     detail: "From home, from work and between places.") {
                                path.append(.travelTimes(nil))
                            }

                            if filtered.isEmpty {
                                EREmptyState(title: "Nothing Matches",
                                             message: "No place here answers to “\(search)”.",
                                             primaryTitle: "Clear the Search",
                                             primaryAction: { search = ""; filter = nil })
                            } else {
                                ERSectionHeader(text: "All Places", trailing: "\(filtered.count)")
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, place in
                                    PlaceRow(place: place,
                                             index: index,
                                             subtitle: subtitle(for: place),
                                             warning: store.wastedWarning(for: place.id)) {
                                        path.append(.detail(place.id))
                                    }
                                    .erAppear(index)
                                }
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
            .navigationDestination(for: PlacesRoute.self) { route in
                switch route {
                case .detail(let id):
                    PlaceDetailView(placeID: id)
                        .navigationBarHidden(true)
                case .travelTimes(let focus):
                    TravelTimesView(focusPlaceID: focus)
                        .navigationBarHidden(true)
                }
            }
        }
        .sheet(isPresented: $creating) {
            PlaceEditorView()
                .environmentObject(store)
        }
        .sheet(item: $editing) { place in
            PlaceEditorView(existing: place)
                .environmentObject(store)
        }
    }

    private func subtitle(for place: Place) -> String {
        let errands = store.errands(at: place).filter { $0.state == .open }.count
        let knowledge = store.planner.queue(for: place.id)
        var parts: [String] = []
        if errands > 0 { parts.append("\(errands) open errand\(errands == 1 ? "" : "s")") }
        parts.append(knowledge.learned ? "your average \(knowledge.averageInside) min" : "your estimate \(knowledge.userEstimate) min")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Detail

struct PlaceDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var placeID: UUID

    @State private var editing = false
    @State private var loggingWaste = false
    @State private var showTravel = false

    private var place: Place? { store.data.place(placeID) }

    var body: some View {
        ERScreen(sparkSeed: 6) {
            ScrollView {
                if let place {
                    VStack(alignment: .leading, spacing: 20) {
                        ERNavBar(title: place.name, onBack: { dismiss() },
                                 trailing: AnyView(ERIconButton(systemName: "pencil") { editing = true }))

                        if let warning = store.wastedWarning(for: place.id) {
                            ERCard(tone: .active) {
                                Text(warning)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        ERCard(index: 1, tone: place.isOpen(on: Date()) ? .idle : .blocked) {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "Today")
                                Text(place.hours(on: Date()).text)
                                    .font(.erHours)
                                    .foregroundStyle(place.isOpen(on: Date()) ? ER.charcoal : ER.scarlet)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !place.address.isEmpty {
                                    Text(place.address)
                                        .font(.erBody)
                                        .foregroundStyle(ER.charcoal.opacity(0.75))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                ERTag(text: place.category.title, color: ER.cherry)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Opening Hours")
                            ERCard(index: 2) {
                                VStack(alignment: .leading, spacing: 7) {
                                    ForEach(ERTime.weekOrder, id: \.self) { weekday in
                                        ERKeyValueRow(key: ERTime.weekdayName(weekday),
                                                      value: place.hours[weekday].isOpen ? place.hours[weekday].text : "Closed")
                                    }
                                }
                            }
                        }

                        queueSection(place: place)

                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Travel")
                            travelCard(place: place)
                        }

                        errandsSection(place: place)

                        if !place.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "Notes")
                                ERCard(index: 5) {
                                    Text(place.notes)
                                        .font(.erBody)
                                        .foregroundStyle(ER.charcoal)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        if !place.photos.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ERSectionHeader(text: "Photos")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(place.photos, id: \.self) { name in
                                            if let image = UIImage(contentsOfFile: store.photoURL(name).path) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 140, height: 140)
                                                    .clipShape(BeveledRect(radius: 10, cap: 12))
                                                    .overlay { BeveledRect(radius: 10, cap: 12).stroke(ER.charcoal, lineWidth: 2.5) }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        wastedSection(place: place)

                        Button("Log a Wasted Trip") { loggingWaste = true }
                            .buttonStyle(GhostButtonStyle())

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ERNavBar(title: "Place", onBack: { dismiss() })
                        EREmptyState(title: "Place Deleted",
                                     message: "This place is no longer in your list.",
                                     primaryTitle: "Go Back",
                                     primaryAction: { dismiss() })
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let place {
                PlaceEditorView(existing: place)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $loggingWaste) {
            if let place {
                WastedTripEditor(place: place)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showTravel) {
            TravelTimesView(focusPlaceID: placeID)
                .environmentObject(store)
        }
    }

    private func queueSection(place: Place) -> some View {
        let knowledge = store.planner.queue(for: place.id)
        return VStack(alignment: .leading, spacing: 10) {
            ERSectionHeader(text: "How Long It Takes Here")
            ERCard(index: 3, tone: knowledge.learned ? .done : .waiting, glow: knowledge.learned) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(knowledge.sentence)
                        .font(.erBodyBold)
                        .foregroundStyle(ER.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    if knowledge.learned {
                        ERKeyValueRow(key: "Planning allowance", value: "\(knowledge.allowance) min on top of the errand")
                        if let note = store.learningNote(for: place.id) {
                            Text(note)
                                .font(.erCaption)
                                .foregroundStyle(ER.cherry)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("The app never shows anyone else's numbers and never claims to know the queue right now.")
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func travelCard(place: Place) -> some View {
        let mode = store.data.settings.travelMode
        let fromHome = store.planner.travel(.home, place.endpoint, mode: mode)
        let fromWork = store.planner.travel(.work, place.endpoint, mode: mode)
        return ERCard(index: 4) {
            VStack(alignment: .leading, spacing: 9) {
                ERKeyValueRow(key: "From home", value: fromHome.minutes.map { "\($0) min" } ?? "not set")
                if !store.data.settings.workAddress.isEmpty {
                    ERKeyValueRow(key: "From work", value: fromWork.minutes.map { "\($0) min" } ?? "not set")
                }
                if let source = fromHome.source {
                    Text(source.title)
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.6))
                }
                Button("Open Travel Times") { showTravel = true }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func errandsSection(place: Place) -> some View {
        let errands = store.errands(at: place).filter { $0.state == .open }
        if !errands.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "Errands Here", trailing: "\(errands.count)")
                ForEach(Array(errands.enumerated()), id: \.element.id) { index, errand in
                    ERCard(index: index, tone: .idle) {
                        HStack {
                            Text(errand.title)
                                .font(.erBodyBold)
                                .foregroundStyle(ER.charcoal)
                            Spacer(minLength: 6)
                            Text("\(errand.duration) min")
                                .font(.erHours)
                                .foregroundStyle(ER.charcoal.opacity(0.7))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wastedSection(place: Place) -> some View {
        let trips = store.wastedTrips(at: place.id)
        if !trips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: "Wasted Trips", trailing: "\(trips.count)")
                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                    ERCard(index: index, tone: .blocked) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(trip.reason.title)
                                    .font(.erBodyBold)
                                    .foregroundStyle(ER.charcoal)
                                Spacer(minLength: 6)
                                Text(ERTime.shortDate(trip.date))
                                    .font(.erHoursSmall)
                                    .foregroundStyle(ER.charcoal.opacity(0.6))
                            }
                            if !trip.missing.isEmpty {
                                Text("Missing: \(trip.missing)")
                                    .font(.erCaption)
                                    .foregroundStyle(ER.charcoal.opacity(0.75))
                            }
                            if !trip.notes.isEmpty {
                                Text(trip.notes)
                                    .font(.erCaption)
                                    .foregroundStyle(ER.charcoal.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}
