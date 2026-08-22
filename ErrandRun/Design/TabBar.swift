//
//  TabBar.swift
//  ErrandRun
//
//  Charcoal bar, diagonal cell dividers, parallelogram indicator.
//

import SwiftUI

enum ERTab: Int, CaseIterable, Identifiable {
    case today, errands, places, runs, insights

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .errands: return "Errands"
        case .places: return "Places"
        case .runs: return "Runs"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .today: return "clock.fill"
        case .errands: return "list.bullet"
        case .places: return "mappin.and.ellipse"
        case .runs: return "arrow.triangle.turn.up.right.diamond.fill"
        case .insights: return "chart.bar.fill"
        }
    }
}

struct ERTabBar: View {
    @Binding var selection: ERTab

    private let height = ERMetric.tabBarHeight
    private let indicatorHeight: CGFloat = 58

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(ERTab.allCases.count)
            let lean = height * tan(ERMetric.bevel * .pi / 180) / 2

            ZStack(alignment: .topLeading) {
                ER.charcoal

                ForEach(1..<ERTab.allCases.count, id: \.self) { index in
                    Path { path in
                        let x = cell * CGFloat(index)
                        path.move(to: CGPoint(x: x + lean, y: 6))
                        path.addLine(to: CGPoint(x: x - lean, y: height - 6))
                    }
                    .stroke(ER.cream.opacity(0.22), lineWidth: 2)
                }

                ParallelogramShape(radius: 9, cap: 12)
                    .fill(.fire)
                    .frame(width: cell - 9, height: indicatorHeight)
                    .offset(x: cell * CGFloat(selection.rawValue) + 4.5, y: 9)

                HStack(spacing: 0) {
                    ForEach(ERTab.allCases) { tab in
                        Button {
                            if selection != tab {
                                withAnimation(.erTab) { selection = tab }
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 17, weight: .black))
                                Text(tab.title.uppercased())
                                    .font(.erTab)
                                    .tracking(0.5)
                            }
                            .foregroundStyle(selection == tab ? ER.cherry : ER.cream.opacity(0.5))
                            .frame(width: cell, height: indicatorHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 9)
            }
        }
        .frame(height: height)
        .background(ER.charcoal.ignoresSafeArea(edges: .bottom))
    }
}
