//
//  PlacePicker.swift
//  ErrandRun
//

import SwiftUI

struct PlacePicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: UUID?

    @State private var search = ""
    @State private var creating = false

    private var places: [Place] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.data.places
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ERScreen(sparkSeed: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ERNavBar(title: "Choose a Place", onBack: { dismiss() })

                    if store.data.places.isEmpty {
                        EREmptyState(title: "No Places Yet",
                                     message: "An errand needs a place before it can be planned: that is where the opening hours live.",
                                     primaryTitle: "Add a Place",
                                     primaryAction: { creating = true })
                    } else {
                        ERTextField(placeholder: "Search", text: $search)

                        Button("New Place") { creating = true }
                            .buttonStyle(GhostButtonStyle())

                        if selection != nil {
                            Button("Clear the Place") {
                                selection = nil
                                dismiss()
                            }
                            .buttonStyle(CancelButtonStyle())
                        }

                        ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                            PlaceRow(place: place,
                                     index: index,
                                     subtitle: place.address.isEmpty ? nil : place.address) {
                                selection = place.id
                                dismiss()
                            }
                            .erAppear(index)
                        }
                    }

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $creating) {
            PlaceEditorView(onSaved: { place in
                selection = place.id
                dismiss()
            })
            .environmentObject(store)
        }
    }
}
