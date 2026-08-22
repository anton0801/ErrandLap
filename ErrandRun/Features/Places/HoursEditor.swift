//
//  HoursEditor.swift
//  ErrandRun
//
//  Opening hours per weekday, with the lunch break and the last entry —
//  the two fields that decide whether a trip is wasted.
//

import SwiftUI

struct HoursEditor: View {
    @Binding var hours: WeeklyHours
    @State private var expanded: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ERNote(text: "A lunch break is the difference between a completed errand and a wasted trip.")

            ForEach(Array(ERTime.weekOrder.enumerated()), id: \.element) { index, weekday in
                dayCard(weekday: weekday, index: index)
            }

            Button("Copy Monday to Tue–Fri") {
                let monday = hours[2]
                withAnimation(.erCard) {
                    for weekday in [3, 4, 5, 6] { hours[weekday] = monday }
                }
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private func dayCard(weekday: Int, index: Int) -> some View {
        let day = hours[weekday]
        let isExpanded = expanded == weekday
        return ERCard(index: index, tone: day.isOpen ? .idle : .dropped) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.erCard) { expanded = isExpanded ? nil : weekday }
                } label: {
                    HStack(spacing: 10) {
                        Text(ERTime.weekdayName(weekday))
                            .font(.erCardTitle)
                            .foregroundStyle(ER.charcoal)
                        Spacer(minLength: 6)
                        Text(day.isOpen ? day.shortText : "Closed")
                            .font(.erHours)
                            .foregroundStyle(day.isOpen ? ER.charcoal.opacity(0.75) : ER.scarlet)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(ER.scarlet)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        ERToggleRow(title: "Open on this day", isOn: binding(weekday).isOpen)

                        if day.isOpen {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    ERSectionHeader(text: "Opens")
                                    ERTimeField(minutes: binding(weekday).open)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    ERSectionHeader(text: "Closes")
                                    ERTimeField(minutes: binding(weekday).close)
                                }
                                Spacer(minLength: 0)
                            }

                            ERToggleRow(title: "Lunch break", isOn: binding(weekday).hasLunch)
                            if day.hasLunch {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ERSectionHeader(text: "From")
                                        ERTimeField(minutes: binding(weekday).lunchStart)
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        ERSectionHeader(text: "To")
                                        ERTimeField(minutes: binding(weekday).lunchEnd)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                ERSectionHeader(text: "Last entry before closing")
                                ERChipRow(items: [0, 10, 15, 30, 45, 60],
                                          title: { $0 == 0 ? "None" : "\($0) min" },
                                          selection: binding(weekday).lastEntryOffset)
                                if day.lastEntryOffset > 0 {
                                    Text("They stop letting people in at \(ERTime.time(day.lastEntry)).")
                                        .font(.erCaption)
                                        .foregroundStyle(ER.cherry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func binding(_ weekday: Int) -> Binding<DayHours> {
        Binding(
            get: { hours[weekday] },
            set: { hours[weekday] = $0 }
        )
    }
}
