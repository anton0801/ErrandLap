//
//  WebPortalView.swift
//  ErrandRun
//
//  ┌──────────────────────────────────────────────────────────────────────────┐
//  │  THIS IS THE PLACE FOR YOUR WEBVIEW.                                     │
//  │                                                                          │
//  │  The screen below is finished: navigation bar, loading and offline       │
//  │  states, the bridge to the page, and the URL to open. The only thing     │
//  │  meant to be replaced is the one line marked SWAP THIS LINE — put your   │
//  │  own web view there and delete `SparkWebView` at the bottom of the file. │
//  │                                                                          │
//  │  Whatever you put in, two things have to be true or the server side      │
//  │  stops working:                                                          │
//  │                                                                          │
//  │  1. A PERSISTENT data store. WKWebView keeps cookies only when it uses   │
//  │     WKWebsiteDataStore.default(). With .nonPersistent() the session      │
//  │     cookie is thrown away when the view goes, the player is a new player │
//  │     on every launch, and it looks like the server forgot them.           │
//  │                                                                          │
//  │  2. Load `WebPortal.url`. It follows the API address, so a debug build   │
//  │     opens the local server and a release build opens the real one.       │
//  └──────────────────────────────────────────────────────────────────────────┘
//

import SwiftUI
import WebKit

enum WebPortal {
    /// The mini-app lives beside the API, so it moves with it.
    /// Change the address in one place: APIConfiguration.baseURL.
    static var url: URL { APIConfiguration.webPortalURL }

    /// The name the page posts to: window.webkit.messageHandlers.errandrun
    static let messageHandler = "errandrun"

    /// What the page sends out. Anything unknown is ignored on purpose, so an
    /// older app never breaks on a newer page.
    enum Message: String {
        case ready
        case roundStarted
        case roundFinished
        case haptic
        case close
    }
}

// MARK: - The screen

struct WebPortalView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var failure: String?
    @State private var reloadToken = 0

    var body: some View {
        ERScreen(sparkSeed: 41) {
            VStack(spacing: 0) {
                ERNavBar(title: "Spark Run", onBack: { dismiss() })
                    .padding(.horizontal, ERMetric.screenPadding)
                    .padding(.top, 14)

                ZStack {
                    // ⬇︎ SWAP THIS LINE for your own web view.
                    SparkWebView(
                        url: WebPortal.url,
                        reloadToken: reloadToken,
                        onLoadingChanged: { isLoading = $0 },
                        onFailure: { failure = $0 },
                        onMessage: handle(_:_:)
                    )
                    .opacity(failure == nil ? 1 : 0)

                    if isLoading && failure == nil {
                        ERLoadingState(text: "Opening Spark Run")
                            .padding(.horizontal, ERMetric.screenPadding)
                    }

                    if let failure {
                        ERErrorState(
                            title: "Could Not Open It",
                            message: failure,
                            retryTitle: "Try Again",
                            retry: {
                                self.failure = nil
                                isLoading = true
                                reloadToken += 1
                            }
                        )
                        .padding(.horizontal, ERMetric.screenPadding)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 10)
            }
        }
    }

    /// What the page asks the app to do. Everything here is optional politeness —
    /// the page works whether or not any of it is implemented.
    private func handle(_ message: WebPortal.Message, _ payload: [String: Any]) {
        switch message {
        case .close:
            dismiss()
        case .haptic:
            let style = payload["style"] as? String ?? "light"
            Haptics.play(style)
        case .ready, .roundStarted, .roundFinished:
            break
        }
    }
}

private enum Haptics {
    static func play(_ style: String) {
        #if canImport(UIKit)
        switch style {
        case "success":
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning":
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }
}

// MARK: - Reference web view — replace this with yours

/// A plain WKWebView wrapper, set up the way the server expects. It is here so
/// the mini-app can be opened and tested straight away; swap in your own and
/// this whole type can go.
struct SparkWebView: UIViewRepresentable {
    let url: URL
    var reloadToken: Int
    var onLoadingChanged: (Bool) -> Void
    var onFailure: (String) -> Void
    var onMessage: (WebPortal.Message, [String: Any]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // The cookie the server sets lives here. A non-persistent store would
        // drop it on every launch — that is the one setting that must not change.
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: WebPortal.messageHandler)
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // The page paints the dark screen itself; a white flash before that would
        // be the only white in the app.
        webView.isOpaque = false
        webView.backgroundColor = UIColor(ER.cherry)
        webView.scrollView.backgroundColor = UIColor(ER.cherry)

        context.coordinator.load(webView, url: url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.load(webView, url: url)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: WebPortal.messageHandler)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: SparkWebView
        var lastReloadToken: Int

        init(_ parent: SparkWebView) {
            self.parent = parent
            self.lastReloadToken = parent.reloadToken
        }

        func load(_ webView: WKWebView, url: URL) {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            parent.onLoadingChanged(true)
            webView.load(request)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        /// Only our own page may open here. A link to anywhere else is refused
        /// rather than followed inside the app.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let allowed = target.host == WebPortal.url.host && target.port == WebPortal.url.port
            decisionHandler(allowed ? .allow : .cancel)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == WebPortal.messageHandler,
                  let body = message.body as? [String: Any],
                  let raw = body["type"] as? String,
                  let known = WebPortal.Message(rawValue: raw) else {
                return
            }
            parent.onMessage(known, body)
        }

        private func report(_ error: Error) {
            parent.onLoadingChanged(false)
            let code = (error as NSError).code
            if code == NSURLErrorCancelled { return }
            parent.onFailure(
                code == NSURLErrorNotConnectedToInternet || code == NSURLErrorCannotConnectToHost
                    ? "No connection. Spark Run needs the network — everything else in the app does not."
                    : error.localizedDescription
            )
        }
    }
}

#Preview {
    WebPortalView()
}
