//
//  TravelTimesView.swift
//  ErrandRun
//
//  Travel is measured once, cached, and only recalculated on request.
//

import SwiftUI

struct TravelPair: Identifiable, Hashable {
    var from: Endpoint
    var to: Endpoint
    var id: String { "\(from.key)>\(to.key)" }
}

struct TravelTimesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// When set, only pairs touching this place are shown.
    var focusPlaceID: UUID? = nil

    @State private var mode: TravelMode = .driving
    @State private var working = false
    @State private var progress = ""
    @State private var errorText: String?
    @State private var manualPair: TravelPair?

    var body: some View {
        ERScreen(sparkSeed: 9) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ERNavBar(title: "Travel Times", onBack: { dismiss() })

                    ERNote(text: "Counted once by the map service, then kept. Nothing is recalculated behind your back.")

                    ERField("Travel Mode") {
                        ERChipRow(items: TravelMode.allCases, title: { $0.title }, selection: $mode)
                    }

                    if let errorText {
                        ERErrorState(title: "Could not measure", message: errorText, retryTitle: "Try Again") {
                            self.errorText = nil
                            Task { await recalculateAll() }
                        }
                    }

                    if working {
                        ERLoadingState(text: progress.isEmpty ? "Measuring" : progress)
                    }

                    group(title: "From Home", pairs: pairs(from: .home))
                    group(title: "From Work", pairs: pairs(from: .work))
                    group(title: "Between Places", pairs: betweenPlaces())

                    if store.data.places.isEmpty {
                        EREmptyState(title: "No Places Yet",
                                     message: "Travel time needs two points. Add a place first.")
                    } else {
                        Button("Recalculate All") {
                            Task { await recalculateAll() }
                        }
                        .buttonStyle(FireButtonStyle())
                        .disabled(working)
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
        .onAppear { mode = store.data.settings.travelMode }
        .sheet(item: $manualPair) { pair in
            ManualTravelSheet(pair: pair, mode: mode)
                .environmentObject(store)
        }
    }

    // MARK: Pairs

    private func pairs(from endpoint: Endpoint) -> [TravelPair] {
        let address = store.data.address(for: endpoint)
        guard !address.isEmpty else { return [] }
        return store.data.places
            .filter { focusPlaceID == nil || $0.id == focusPlaceID }
            .map { TravelPair(from: endpoint, to: .place($0.id)) }
    }

    private func betweenPlaces() -> [TravelPair] {
        var result: [TravelPair] = []
        let places = store.data.places
        for (index, place) in places.enumerated() {
            for other in places.dropFirst(index + 1) {
                if let focusPlaceID, place.id != focusPlaceID, other.id != focusPlaceID { continue }
                result.append(TravelPair(from: .place(place.id), to: .place(other.id)))
            }
        }
        return result
    }

    @ViewBuilder
    private func group(title: String, pairs: [TravelPair]) -> some View {
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ERSectionHeader(text: title, trailing: "\(pairs.count)")
                ForEach(Array(pairs.enumerated()), id: \.element.id) { index, pair in
                    row(pair: pair, index: index)
                }
            }
        }
    }

    private func row(pair: TravelPair, index: Int) -> some View {
        let lookup = store.planner.travel(pair.from, pair.to, mode: mode)
        return ERCard(index: index, tone: lookup.known ? .idle : .waiting) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.data.name(for: pair.from).capitalized)
                        .font(.erBodyBold)
                        .foregroundStyle(ER.charcoal)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(ER.scarlet)
                    Text(store.data.name(for: pair.to).capitalized)
                        .font(.erBodyBold)
                        .foregroundStyle(ER.charcoal)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if let minutes = lookup.minutes {
                        Text("\(minutes) min")
                            .font(.erHours)
                            .foregroundStyle(ER.charcoal)
                    } else {
                        Text("not set")
                            .font(.erCaption)
                            .foregroundStyle(ER.scarlet)
                    }
                }

                if let source = lookup.source {
                    Text(source.title)
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.6))
                }

                HStack(spacing: 8) {
                    Button("By Hand") { manualPair = pair }
                        .buttonStyle(.plain)
                        .font(.erCaption)
                        .foregroundStyle(ER.cherry)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .overlay { BeveledRect(radius: 8, cap: 8).stroke(ER.charcoal, lineWidth: 2) }

                    Button("Recalculate") {
                        Task { await recalculate(pair: pair) }
                    }
                    .buttonStyle(.plain)
                    .font(.erCaption)
                    .foregroundStyle(ER.cherry)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background { BeveledRect(radius: 8, cap: 8).fill(.fire) }
                    .disabled(working)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Measuring

    private func recalculate(pair: TravelPair) async {
        working = true
        errorText = nil
        progress = "Measuring \(store.data.name(for: pair.to))"
        defer {
            working = false
            progress = ""
        }
        await measure(pair: pair)
    }

    private func recalculateAll() async {
        working = true
        errorText = nil
        var all = pairs(from: .home) + pairs(from: .work) + betweenPlaces()
        all = Array(all.prefix(60))
        for (index, pair) in all.enumerated() {
            progress = "Measuring \(index + 1) of \(all.count)"
            let ok = await measure(pair: pair)
            if !ok, errorText != nil { break }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        working = false
        progress = ""
    }

    @discardableResult
    private func measure(pair: TravelPair) async -> Bool {
        guard let from = await coordinate(for: pair.from), let to = await coordinate(for: pair.to) else {
            errorText = "One of these two points has no address that could be located. Enter the travel time by hand."
            return false
        }
        do {
            let minutes = try await TravelService.minutes(from: from, to: to, mode: mode, pace: store.data.settings.walkingPace)
            store.setTravel(from: pair.from, to: pair.to, mode: mode, minutes: minutes, source: .map)
            return true
        } catch {
            errorText = (error as? TravelError)?.errorDescription ?? "Could not measure this route."
            return false
        }
    }

    /// Looks up the stored coordinate, geocoding the address if it has never been located.
    private func coordinate(for endpoint: Endpoint) async -> GeoPoint? {
        if let point = store.data.coordinate(for: endpoint) { return point }
        let address = store.data.address(for: endpoint)
        guard !address.isEmpty, let point = try? await TravelService.geocode(address) else { return nil }
        store.mutate { data in
            switch endpoint {
            case .home: data.settings.homeCoordinate = point
            case .work: data.settings.workCoordinate = point
            case .place(let id):
                if let index = data.places.firstIndex(where: { $0.id == id }) {
                    data.places[index].coordinate = point
                }
            case .custom: break
            }
        }
        return point
    }
}

// MARK: - Manual entry

struct ManualTravelSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var pair: TravelPair
    var mode: TravelMode

    @State private var minutes = 10

    var body: some View {
        ERScreen(sparkSeed: 12) {
            VStack(alignment: .leading, spacing: 20) {
                ERNavBar(title: "Travel Time", onBack: { dismiss() })

                Text("\(store.data.name(for: pair.from).capitalized) → \(store.data.name(for: pair.to).capitalized)")
                    .font(.erCardTitle)
                    .foregroundStyle(ER.charcoal)

                ERNote(text: "Offline, or the map is wrong about your street? Enter the number you know is true.")

                ERCard {
                    ERStepperRow(title: "Takes", value: $minutes, range: 1...240, step: 1)
                }

                ERChipRow(items: [5, 10, 15, 20, 30, 45, 60], title: { "\($0) min" }, selection: $minutes)

                Button("Save Travel Time") {
                    store.setTravel(from: pair.from, to: pair.to, mode: mode, minutes: minutes, source: .manual)
                    dismiss()
                }
                .buttonStyle(FireButtonStyle())

                Button("Clear It") {
                    store.clearTravel(from: pair.from, to: pair.to, mode: mode)
                    dismiss()
                }
                .buttonStyle(GhostButtonStyle())

                Spacer()
            }
            .padding(.horizontal, ERMetric.screenPadding)
            .padding(.top, 16)
        }
        .onAppear {
            if let existing = store.planner.travel(pair.from, pair.to, mode: mode).minutes {
                minutes = existing
            }
        }
    }
}
