//
//  OnboardingView.swift
//  ErrandRun
//

import SwiftUI

struct OnboardingPage: Identifiable {
    var id: Int
    var title: String
    var body: String
    var detail: String
}

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "A List Is Not a Plan",
            body: "A list of errands does not know that the post office closes at two, and that it is twenty minutes away.",
            detail: "Errand Run takes your free time, the opening hours of every place and the real travel between them, and works out what you can actually finish today."
        ),
        OnboardingPage(
            id: 1,
            title: "Opening Hours Beat Priorities",
            body: "The order of your errands is decided by doors, not by importance.",
            detail: "What closes earliest goes first, even when it matters less. You can always reorder by hand — the app will tell you straight away what that costs you."
        ),
        OnboardingPage(
            id: 2,
            title: "Nobody Knows the Queue",
            body: "This app will never promise you fifteen minutes at the clinic.",
            detail: "It asks for your own estimate, remembers how long it really took, and after a few visits it plans with your numbers instead of your hopes."
        ),
        OnboardingPage(
            id: 3,
            title: "Add Your First Errand",
            body: "Set up where you start from and how you move. Then add the first thing you have been putting off.",
            detail: AppMode.onboardingStorageLine
        )
    ]

    var body: some View {
        ERScreen(sparkSeed: page + 2) {
            VStack(alignment: .leading, spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages) { item in
                        pageView(item)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                indicators
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.bottom, 14)

                VStack(spacing: 10) {
                    Button(page == pages.count - 1 ? "Set Up and Start" : "Next") {
                        if page == pages.count - 1 {
                            var settings = store.data.settings
                            settings.onboardingSeen = true
                            store.mutate { $0.settings = settings }
                        } else {
                            withAnimation(.erCard) { page += 1 }
                        }
                    }
                    .buttonStyle(FireButtonStyle())

                    if page < pages.count - 1 {
                        Button("Skip the Tour") {
                            var settings = store.data.settings
                            settings.onboardingSeen = true
                            store.mutate { $0.settings = settings }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.bottom, 24)
            }
        }
    }

    private func pageView(_ item: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SparkField(seed: item.id + 3, count: 9)
                .frame(height: 120)
            Text("\(item.id + 1) of \(pages.count)")
                .font(.erSection)
                .tracking(1)
                .foregroundStyle(ER.charcoal.opacity(0.5))
            ERScreenTitle(text: item.title)
            Text(item.body)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ER.charcoal)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.detail)
                .font(.erBody)
                .foregroundStyle(ER.charcoal.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ERMetric.screenPadding)
    }

    private var indicators: some View {
        HStack(spacing: 8) {
            ForEach(pages) { item in
                DiamondShape()
                    .fill(item.id == page ? AnyShapeStyle(.fire) : AnyShapeStyle(ER.charcoal.opacity(0.25)))
                    .frame(width: item.id == page ? 14 : 9, height: item.id == page ? 14 : 9)
                    .animation(.erTab, value: page)
            }
            Spacer()
        }
    }
}
