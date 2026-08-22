//
//  SyncStatusView.swift
//  ErrandRun
//
//  What the "Sync & Account" row opens while the app is in local mode.
//
//  The screen exists so the slot in Settings does not move when the server comes
//  online: in connected mode the same row opens AccountView instead, and this
//  file is not reached. Nothing here is a placeholder for the user — it answers
//  the question they actually have, which is "where is my data".
//

import SwiftUI

struct SyncStatusView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var counts: (errands: Int, places: Int, runs: Int) {
        (store.data.errands.count, store.data.places.count, store.data.runs.count)
    }

    var body: some View {
        ERScreen(sparkSeed: 43) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ERNavBar(title: "Your Data", onBack: { dismiss() })

                    ERCard(tone: .done, glow: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Where It Lives")
                            Text("On this phone")
                                .font(.erCardTitle)
                                .foregroundStyle(ER.charcoal)
                            Text("Everything you enter is written to this device and nowhere else. No account, no sign-up, and nothing leaves the phone.")
                                .font(.erBody)
                                .foregroundStyle(ER.charcoal.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ERSectionHeader(text: "Kept Here")
                        ERCard(index: 1) {
                            VStack(alignment: .leading, spacing: 8) {
                                ERKeyValueRow(key: "Errands", value: "\(counts.errands)")
                                ERKeyValueRow(key: "Places", value: "\(counts.places)")
                                ERKeyValueRow(key: "Runs", value: "\(counts.runs)")
                            }
                        }
                    }

                    ERCard(index: 2) {
                        VStack(alignment: .leading, spacing: 10) {
                            ERSectionHeader(text: "Two Things Worth Knowing")
                            bullet("Deleting the app deletes the data with it. Settings → Data → Export Data writes it out first.")
                            bullet("Sync between devices is coming in an update. When it arrives, what is already on this phone moves across on its own — nothing has to be typed in twice.")
                        }
                    }

                    ERNote(text: "The map service is used for one thing only: the real travel time between two points. That request is made by this phone.")

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 14)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            DiamondShape()
                .fill(.fire)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            Text(text)
                .font(.erCaption)
                .foregroundStyle(ER.charcoal.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
