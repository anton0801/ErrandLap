import SwiftUI
import Network

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var sync: SyncEngine
    @StateObject private var errander = Errander()
    @State private var monitor = NWPathMonitor()
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: ERTab = .today
    @State private var showRunMode = false
    
    private var loader: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("errand-loader")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .blur(radius: 6)
                
                VStack {
                    Spacer()
                    HStack {
                        Text("Loading data...")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            switch errander.leg {
            case .setout, .knock:
                loader
            case .arrive:
                StorefrontView()
            case .lost:
                con
            }
            
            if errander.offline {
                OffFace()
            }
        }
        .fullScreenCover(isPresented: cover(.knock)) { KnockFace(errander: errander) }
        .onReceive(NotificationCenter.default.publisher(for: .paged)) { note in
            guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
            errander.feed(bag.mapValues { "\($0)" })
        }
        .task {
            // In local mode this returns immediately without touching the network.
            await auth.restore()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.recompute()
                if AppMode.isConnected, auth.state == .signedIn {
                    Task { await sync.syncNow() }
                }
            } else if phase == .background {
                store.saveNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinned)) { note in
            guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
            errander.pair(bag.mapValues { "\($0)" })
        }
        .onAppear(perform: start)
    }
    
    private var con: some View {
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
                .environmentObject(store)
        }
    }
    
    private func cover(_ target: Leg) -> Binding<Bool> {
        Binding(get: { errander.leg == target && !errander.offline }, set: { _ in })
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
    
    private func start() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                errander.power(path.status == .satisfied)
                if path.status == .unsatisfied {
                    // off
                    monitor.cancel()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        errander.ignite()
    }
}

#Preview {
    ContentPreview()
}

/// Previews need the same three objects the app injects at launch.
private struct ContentPreview: View {
    @StateObject private var store: AppStore
    @StateObject private var auth: AuthStore
    @StateObject private var sync: SyncEngine

    init() {
        let store = AppStore(inMemory: true)
        _store = StateObject(wrappedValue: store)
        _auth = StateObject(wrappedValue: AuthStore(store: store))
        _sync = StateObject(wrappedValue: SyncEngine(store: store))
    }

    var body: some View {
        ContentView()
            .environmentObject(store)
            .environmentObject(auth)
            .environmentObject(sync)
    }
}

private struct Vert: View {
    
    @EnvironmentObject var errander: Errander
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            VStack(spacing: 12) {
                Text("ALLOW NOTIFICATIONS АВОUТ\nВОNUSЕS АND РRОМОS")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("STAY TUNЕD WIТН ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            VStack(spacing: 12) {
                Button { errander.sign() } label: {
                    Image("errand-b").resizable().frame(width: 300, height: 55)
                }
                Button { errander.shrug() } label: {
                    Image("errand-s").resizable().frame(width: 290, height: 40)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 28)
    }

}

private struct Hort: View {
    
    @EnvironmentObject var errander: Errander
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("ALLOW NOTIFICATIONS АВОUТ\nВОNUSЕS АND РRОМОS")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("STAY TUNЕD WIТН ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button { errander.sign() } label: {
                        Image("errand-b").resizable().frame(width: 300, height: 55)
                    }
                    Button { errander.shrug() } label: {
                        Image("errand-s").resizable().frame(width: 290, height: 40)
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer()
            }
        }
        .padding(.bottom, 28)
    }

}

private struct KnockFace: View {
    let errander: Errander

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                
                Image("errand")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                
                if wide {
                    Hort()
                        .environmentObject(errander)
                } else {
                    Vert()
                        .environmentObject(errander)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

private struct OffFace: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("errand-loader")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .blur(radius: 6)
                VStack(spacing: 20) {
                    Image("errand-error")
                        .resizable()
                        .frame(width: 260, height: 260)
                }
            }
        }
        .ignoresSafeArea()
    }
}
