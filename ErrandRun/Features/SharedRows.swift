//
//  SharedRows.swift
//  ErrandRun
//
//  Rows and the diagonal route ribbon, used across screens.
//

import SwiftUI

// MARK: - Errand row

struct ErrandRow: View {
    var errand: Errand
    var placeName: String?
    var section: ErrandSection
    var index: Int
    var note: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ERCard(index: index, tone: section.tone, glow: section == .done) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: errand.category.icon)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(ER.scarlet)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(errand.title)
                                .font(.erCardTitle)
                                .foregroundStyle(ER.charcoal)
                                .multilineTextAlignment(.leading)
                            Text(placeName ?? "No place yet")
                                .font(.erCaption)
                                .foregroundStyle(placeName == nil ? ER.scarlet : ER.charcoal.opacity(0.65))
                        }
                        Spacer(minLength: 4)
                        Text("\(errand.duration)")
                            .font(.erHours)
                            .foregroundStyle(ER.charcoal)
                        + Text(" min")
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.6))
                    }

                    if let note {
                        Text(note)
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 6) {
                        if section != .open {
                            ERTag(text: section.rawValue, color: section.tone.color, filled: section == .done)
                        }
                        if errand.priority == .high {
                            ERTag(text: "High", color: ER.scarlet)
                        }
                        if let deadline = errand.deadline {
                            ERTag(text: "By \(ERTime.shortDate(deadline))", color: ER.cherry)
                        }
                        if errand.recurrence != nil {
                            ERTag(text: "Repeats", color: ER.orange)
                        }
                        if errand.canBeDelegated {
                            ERTag(text: "Can delegate", color: ER.charcoal.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Place row

struct PlaceRow: View {
    var place: Place
    var index: Int
    var subtitle: String? = nil
    var warning: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ERCard(index: index, tone: .idle) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: place.category.icon)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(ER.scarlet)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name)
                                .font(.erCardTitle)
                                .foregroundStyle(ER.charcoal)
                                .multilineTextAlignment(.leading)
                            Text(place.hours(on: Date()).text)
                                .font(.erHoursSmall)
                                .foregroundStyle(place.isOpen(on: Date()) ? ER.charcoal.opacity(0.7) : ER.scarlet)
                        }
                        Spacer(minLength: 0)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.erCaption)
                            .foregroundStyle(ER.charcoal.opacity(0.65))
                            .multilineTextAlignment(.leading)
                    }
                    if let warning {
                        Text(warning)
                            .font(.erCaption)
                            .foregroundStyle(ER.scarlet)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Route ribbon

struct RouteStopCard: View {
    var stop: StopPlan
    var index: Int
    var isCurrent: Bool
    var isDone: Bool
    var isSkipped: Bool
    var dark: Bool
    var mode: TravelMode
    var showQueueBreakdown: Bool = true

    private var tone: ERStatusTone {
        if isDone { return .done }
        if isSkipped { return .dropped }
        if isCurrent { return .active }
        return .idle
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isCurrent {
                SparkField(seed: index + 11, count: 6, bright: dark)
                    .padding(-10)
            }
            ERCard(index: index, tone: tone, glow: isDone, dark: dark) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ERTime.time(stop.startInside))
                            .font(.erHours)
                            .foregroundStyle(dark ? ER.gold : ER.charcoal)
                        Text(stop.place.name)
                            .font(.erCardTitle)
                            .foregroundStyle(dark ? ER.cream : ER.charcoal)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: stop.errand.category.icon)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(isDone ? ER.gold : ER.scarlet)
                    }

                    Text(stop.errand.title)
                        .font(.erBody)
                        .foregroundStyle(dark ? ER.cream.opacity(0.85) : ER.charcoal.opacity(0.8))
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        ERTag(text: "\(stop.travel) min \(mode.noun)", color: dark ? ER.gold : ER.charcoal.opacity(0.7))
                        ERTag(text: "\(stop.inside) min inside", color: dark ? ER.gold : ER.charcoal.opacity(0.7))
                        if stop.wait > 0 {
                            ERTag(text: "\(stop.wait) min wait", color: ER.orange)
                        }
                        Spacer(minLength: 0)
                    }

                    if showQueueBreakdown {
                        Text("\(stop.errand.duration) min for the errand + \(stop.queue) min of queue allowance.")
                            .font(.erCaption)
                            .foregroundStyle(dark ? ER.cream.opacity(0.6) : ER.charcoal.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 6) {
                        if let close = stop.close {
                            Text("Closes \(ERTime.time(close))")
                                .font(.erHoursSmall)
                                .foregroundStyle(dark ? ER.cream.opacity(0.75) : ER.charcoal.opacity(0.7))
                        }
                        if let lastEntry = stop.lastEntry {
                            Text("· last entry \(ERTime.time(lastEntry))")
                                .font(.erHoursSmall)
                                .foregroundStyle(ER.scarlet)
                        }
                        Spacer(minLength: 0)
                        if stop.tight { ERTag(text: "Tight", color: ER.scarlet) }
                        if isDone { ERTag(text: "Done", color: ER.gold, filled: true) }
                        if isSkipped { ERTag(text: "Skipped", color: ER.charcoal.opacity(0.5)) }
                    }

                    if stop.errand.requiresDocuments, !stop.errand.documents.isEmpty {
                        Text("Take: " + stop.errand.documents.joined(separator: ", "))
                            .font(.erCaption)
                            .foregroundStyle(dark ? ER.gold : ER.cherry)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }
}

struct RouteConnector: View {
    var dark: Bool

    var body: some View {
        ZStack(alignment: .center) {
            Path { path in
                path.move(to: CGPoint(x: 8, y: 38))
                path.addLine(to: CGPoint(x: 30, y: 0))
            }
            .stroke(LinearGradient.fire(), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: 38, height: 38)

            DiamondShape()
                .fill(dark ? ER.gold : ER.cherry)
                .frame(width: 10, height: 10)
                .offset(x: 19 - 19, y: 0)
        }
        .frame(width: 38, height: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 26)
    }
}

/// Bottom to top, drifting right. The current point is bigger.
struct RouteRibbon: View {
    var stops: [StopPlan]
    var mode: TravelMode
    var currentID: UUID? = nil
    var doneIDs: Set<UUID> = []
    var skippedIDs: Set<UUID> = []
    var dark: Bool = false
    var onTap: ((StopPlan) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()).reversed(), id: \.element.id) { index, stop in
                let isCurrent = stop.id == currentID
                Group {
                    if let onTap {
                        Button { onTap(stop) } label: { card(stop: stop, index: index, isCurrent: isCurrent) }
                            .buttonStyle(.plain)
                    } else {
                        card(stop: stop, index: index, isCurrent: isCurrent)
                    }
                }
                .padding(.leading, CGFloat(index) * 11)
                .padding(.trailing, CGFloat(stops.count - 1 - index) * 3)
                .scaleEffect(isCurrent ? 1.15 : 1, anchor: .center)
                .padding(.vertical, isCurrent ? 10 : 0)
                .zIndex(isCurrent ? 2 : 1)
                .erAppear(index)

                if index > 0 {
                    RouteConnector(dark: dark)
                        .padding(.leading, CGFloat(index - 1) * 11)
                }
            }
        }
    }

    private func card(stop: StopPlan, index: Int, isCurrent: Bool) -> some View {
        RouteStopCard(stop: stop,
                      index: index,
                      isCurrent: isCurrent,
                      isDone: doneIDs.contains(stop.id),
                      isSkipped: skippedIDs.contains(stop.id),
                      dark: dark,
                      mode: mode)
    }
}

// MARK: - Did not fit

struct MissedCard: View {
    var missed: MissedErrand
    var index: Int
    var dark: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        ERCard(index: index, tone: .waiting, dark: dark) {
            VStack(alignment: .leading, spacing: 8) {
                Text(missed.place?.name ?? missed.errand.title)
                    .font(.erCardTitle)
                    .foregroundStyle(dark ? ER.cream : ER.charcoal)
                Text(missed.errand.title)
                    .font(.erCaption)
                    .foregroundStyle(dark ? ER.cream.opacity(0.7) : ER.charcoal.opacity(0.65))
                Text(missed.reason)
                    .font(.erBody)
                    .foregroundStyle(dark ? ER.cream.opacity(0.9) : ER.charcoal.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let suggestion = missed.suggestion {
                    Text(suggestion)
                        .font(.erCaption)
                        .foregroundStyle(ER.cherry)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("No window in the next three weeks fits this one. It stays in the queue.")
                        .font(.erCaption)
                        .foregroundStyle(ER.charcoal.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                if let action {
                    Button("Open the Errand", action: action)
                        .buttonStyle(GhostButtonStyle(dark: dark))
                        .padding(.top, 2)
                }
            }
        }
    }
}
