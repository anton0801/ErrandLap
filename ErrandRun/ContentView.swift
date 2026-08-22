//
//  ContentView.swift
//  ErrandRun
//

import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(SyncEngine.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: ERTab = .today
    @State private var showRunMode = false

    var body: some View {
        Group {
            if store.isLoading || auth.state == .restoring {
                ERScreen {
                    VStack(alignment: .leading) {
                        ERScreenTitle(text: "Errand Run")
                        ERLoadingState(text: "Opening your errands")
                    }
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 60)
                }
            } else if !store.data.settings.onboardingSeen {
                OnboardingView()
                    .transition(.opacity)
            } else if AppMode.isConnected, auth.state == .signedOut {
                AuthView()
                    .transition(.opacity)
            } else if !store.data.settings.setupComplete {
                SetupView(isInitial: true)
                    .transition(.opacity)
            } else {
                main
                    .transition(.opacity)
            }
        }
        .animation(.erCard, value: store.data.settings.onboardingSeen)
        .animation(.erCard, value: store.data.settings.setupComplete)
        .animation(.erCard, value: auth.state)
        .fullScreenCover(isPresented: $showRunMode) {
            RunModeView()
                .environment(store)
        }
        .task {
            // In local mode this returns immediately without touching the network.
            await auth.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.recompute()
                if AppMode.isConnected, auth.state == .signedIn {
                    Task { await sync.syncNow() }
                }
            } else if phase == .background {
                store.saveNow()
            }
        }
    }

    private var main: some View {
        ZStack(alignment: .bottom) {
            (ER.cream).ignoresSafeArea()

            Group {
                switch tab {
                case .today:
                    TodayView(selectTab: { tab = $0 }, openRunMode: { showRunMode = true })
                case .errands:
                    ErrandsView()
                case .places:
                    PlacesView()
                case .runs:
                    RunsView(openRunMode: { showRunMode = true })
                case .insights:
                    InsightsView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: ERMetric.tabBarHeight)
            }

            ERTabBar(selection: $tab)
        }
    }
}

#Preview {
    let store = AppStore(inMemory: true)
    return ContentView()
        .environment(store)
        .environment(AuthStore(store: store))
        .environment(SyncEngine(store: store))
}
