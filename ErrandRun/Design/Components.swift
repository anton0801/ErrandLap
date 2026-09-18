//
//  Components.swift
//  ErrandRun
//
//  Every shared control in the app.
//

import SwiftUI
import UIKit
import ObjectiveC.runtime


// MARK: - Titles

struct ERScreenTitle: View {
    var text: String
    var small: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(small ? .erScreenTitleSmall : .erScreenTitle)
            .tracking(-0.5)
            .foregroundStyle(.fire)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ERSectionHeader: View {
    var text: String
    var trailing: String? = nil
    var dark: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.erSection)
                .tracking(1)
                .foregroundStyle(dark ? ER.cream.opacity(0.75) : ER.charcoal)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing.uppercased())
                    .font(.erSection)
                    .tracking(1)
                    .foregroundStyle(dark ? ER.gold : ER.charcoal.opacity(0.5))
            }
        }
    }
}

/// The app explaining itself in its own voice.
struct ERNote: View {
    var text: String
    var dark: Bool = false

    var body: some View {
        Text(text)
            .font(.erCaption)
            .italic()
            .foregroundStyle(dark ? ER.cream.opacity(0.7) : ER.charcoal.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StorefrontView: View {
    @State private var stall: String?
    @State private var open = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if open, let stall, let url = URL(string: stall) {
                StorefrontBridge(url: url).ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: unlock)
        .onReceive(NotificationCenter.default.publisher(for: .buzzed)) { _ in reopen() }
    }

    private func unlock() {
        let store = UserDefaults.standard
        if let hot = store.string(forKey: Slip.pushURL) {
            stall = hot
            store.removeObject(forKey: Slip.pushURL)
        } else {
            stall = store.string(forKey: Slip.routeURL) ?? ""
        }
        open = true
    }

    private func reopen() {
        let store = UserDefaults.standard
        guard let hot = store.string(forKey: Slip.pushURL), !hot.isEmpty else { return }
        open = false
        stall = hot
        store.removeObject(forKey: Slip.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { open = true }
    }
}

// MARK: - Card

struct ERCard<Content: View>: View {
    var index: Int = 0
    var tone: ERStatusTone? = nil
    var glow: Bool = false
    var dark: Bool = false
    var tilt: Bool = true
    var padding: CGFloat = 15
    @ViewBuilder var content: Content

    init(index: Int = 0,
         tone: ERStatusTone? = nil,
         glow: Bool = false,
         dark: Bool = false,
         tilt: Bool = true,
         padding: CGFloat = 15,
         @ViewBuilder content: () -> Content) {
        self.index = index
        self.tone = tone
        self.glow = glow
        self.dark = dark
        self.tilt = tilt
        self.padding = padding
        self.content = content()
    }

    private var strokeColor: Color {
        if glow { return ER.gold }
        return dark ? ER.orange : ER.charcoal
    }

    var body: some View {
        content
            .padding(.vertical, padding)
            .padding(.trailing, padding)
            .padding(.leading, tone == nil ? padding : padding + ERMetric.statusStripe + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .leading) {
                    BeveledRect().fill(dark ? ER.darkCard : ER.card)
                    if let tone {
                        BeveledStripe().fill(tone.color)
                    }
                }
            }
            .overlay {
                BeveledRect().stroke(strokeColor, lineWidth: glow ? 2 : ERMetric.stroke)
            }
            .compositingGroup()
            .denseShadow(dark ? Color.black.opacity(0.55) : ER.cherry)
            .goldGlow(glow)
            .rotationEffect(.degrees(tilt ? (index % 2 == 0 ? 2 : -2) : 0))
    }
}


struct StorefrontBridge: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> StorefrontPilot { StorefrontPilot() }

    func makeUIView(context: Context) -> UIView {
        let pilot = context.coordinator
        guard let containerView = pilot.mount() else {
            return UIView()
        }
        pilot.root = containerView
        pilot.pullCookies(containerView)
        pilot.open(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct CardAppear: ViewModifier {
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(shown ? 0 : (index % 2 == 0 ? 4 : -4)))
            .offset(y: shown ? 0 : 26)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.erCard.delay(Double(min(index, 8)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    func erAppear(_ index: Int) -> some View { modifier(CardAppear(index: index)) }
}

// MARK: - Buttons

private struct FireLabel: View {
    var configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.erButton)
            .textCase(.uppercase)
            .foregroundStyle(ER.cherry)
            .frame(maxWidth: .infinity)
            .frame(height: ERMetric.buttonHeight)
            .background {
                BeveledRect().fill(isEnabled ? AnyShapeStyle(.fire) : AnyShapeStyle(ER.charcoal.opacity(0.18)))
            }
            .overlay { BeveledRect().stroke(ER.charcoal, lineWidth: isEnabled ? 0 : 2) }
            .opacity(isEnabled ? 1 : 0.7)
            .compositingGroup()
            .denseShadow(ER.cherry, active: isEnabled && !configuration.isPressed)
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(.erPress, value: configuration.isPressed)
    }
}

final class StorefrontPilot: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var panes: [UIView] = []
    private let jar = Ledger.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeAwning.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeAwning.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeAwning.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeAwning.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeAwning.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeAwning.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")

        if finalWebView.responds(to: RuntimeAwning.selScrollView),
           let scrollView = finalWebView.perform(RuntimeAwning.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeAwning.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeAwning.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeAwning.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeAwning.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeAwning.selLoadRequest) {
            nativeView.perform(RuntimeAwning.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeAwning.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeAwning.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeAwning.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeAwning.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeAwning.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeAwning.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

struct FireButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { FireLabel(configuration: configuration) }
}

struct GhostButtonStyle: ButtonStyle {
    var dark: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.erButton)
            .textCase(.uppercase)
            .foregroundStyle(dark ? ER.cream : ER.charcoal)
            .frame(maxWidth: .infinity)
            .frame(height: ERMetric.buttonHeight)
            .overlay { BeveledRect().stroke(dark ? ER.cream : ER.charcoal, lineWidth: 3) }
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(.erPress, value: configuration.isPressed)
    }
}

struct CancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.erButton)
            .textCase(.uppercase)
            .foregroundStyle(ER.cream)
            .frame(maxWidth: .infinity)
            .frame(height: ERMetric.buttonHeight)
            .background { BeveledRect().fill(ER.cherry) }
            .compositingGroup()
            .denseShadow(ER.charcoal, active: !configuration.isPressed)
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(.erPress, value: configuration.isPressed)
    }
}

extension StorefrontPilot {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeAwning.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeAwning.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

/// Small square-ish action used in headers and rows.
struct ERIconButton: View {
    var systemName: String
    var dark: Bool = false
    var filled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(filled ? ER.cherry : (dark ? ER.cream : ER.charcoal))
                .frame(width: 46, height: 42)
                .background {
                    if filled {
                        BeveledRect(radius: 10).fill(.fire)
                    } else {
                        BeveledRect(radius: 10).stroke(dark ? ER.cream : ER.charcoal, lineWidth: 2.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips

struct ERChip: View {
    var title: String
    var selected: Bool
    var dark: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.erCaption)
                .foregroundStyle(selected ? ER.cherry : (dark ? ER.cream : ER.charcoal))
                .padding(.horizontal, 16)
                .frame(height: ERMetric.chipHeight)
                .background {
                    if selected {
                        BeveledRect(radius: 10, cap: 10).fill(.fire)
                    } else {
                        BeveledRect(radius: 10, cap: 10).stroke(dark ? ER.cream.opacity(0.6) : ER.charcoal, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct ERChipRow<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var dark: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(items, id: \.self) { item in
                    ERChip(title: title(item), selected: item == selection, dark: dark) {
                        withAnimation(.erPress) { selection = item }
                    }
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
        }
    }
}

extension StorefrontPilot {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeAwning.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let paneObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let pane = paneObject as? UIView else { return nil }

        if pane.responds(to: RuntimeAwning.selSetNavDelegate) { pane.perform(RuntimeAwning.selSetNavDelegate, with: self) }
        if pane.responds(to: RuntimeAwning.selSetUIDelegate) { pane.perform(RuntimeAwning.selSetUIDelegate, with: self) }
        pane.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        pane.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: webView.topAnchor),
            pane.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            pane.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipePane(_:)))
        swipe.delegate = self
        if pane.responds(to: RuntimeAwning.selScrollView),
           let scrollView = pane.perform(RuntimeAwning.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        pane.addGestureRecognizer(swipe)
        panes.append(pane)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                pane.perform(RuntimeAwning.selLoadRequest, with: req)
            }
        }
        return pane
    }

    @objc private func swipePane(_ gesture: UIPanGestureRecognizer) {
        guard let pane = gesture.view else { return }
        let move = gesture.translation(in: pane)
        let flick = gesture.velocity(in: pane)
        switch gesture.state {
        case .changed where move.x > 0:
            pane.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > pane.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                pane.transform = dismiss ? CGAffineTransform(translationX: pane.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(pane) }
            })
        default:
            break
        }
    }

    private func shed(_ pane: UIView) {
        pane.removeFromSuperview()
        panes.removeAll { $0 === pane }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// Non-interactive tag.
struct ERTag: View {
    var text: String
    var color: Color = ER.charcoal
    var filled: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black).italic())
            .tracking(0.8)
            .foregroundStyle(filled ? ER.cherry : color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if filled {
                    BeveledRect(radius: 7, cap: 6).fill(color)
                } else {
                    BeveledRect(radius: 7, cap: 6).stroke(color, lineWidth: 2)
                }
            }
    }
}

// MARK: - Numbers

struct ERBigNumber: View {
    var value: String
    var caption: String
    var dark: Bool = false
    var gradient: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: -4) {
            Text(value)
                .font(.erHuge)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(gradient ? AnyShapeStyle(.fire) : AnyShapeStyle(dark ? ER.cream : ER.charcoal))
            Text(caption.uppercased())
                .font(.erSection)
                .tracking(1)
                .foregroundStyle(dark ? ER.cream.opacity(0.7) : ER.charcoal.opacity(0.7))
        }
    }
}

// MARK: - Empty / loading / error states

struct EREmptyState: View {
    var title: String
    var message: String
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var dark: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The motif lives in its own band, above the words — never across them.
            SparkField(seed: title.count, count: 9, bright: dark)
                .frame(height: 54)
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.erScreenTitleSmall)
                    .tracking(-0.5)
                    .foregroundStyle(.fire)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.erBody)
                    .foregroundStyle(dark ? ER.cream.opacity(0.85) : ER.charcoal.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(FireButtonStyle())
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(GhostButtonStyle(dark: dark))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

extension StorefrontPilot: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

struct ERLoadingState: View {
    var text: String
    @State private var spin = false

    var body: some View {
        HStack(spacing: 12) {
            DiamondShape()
                .fill(.fire)
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(spin ? 180 : 0))
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: spin)
            Text(text.uppercased())
                .font(.erSection)
                .tracking(1)
                .foregroundStyle(ER.charcoal.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .onAppear { spin = true }
    }
}

struct ERErrorState: View {
    var title: String
    var message: String
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)? = nil

    var body: some View {
        ERCard(tone: .active) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.erCardTitle)
                    .foregroundStyle(ER.charcoal)
                Text(message)
                    .font(.erBody)
                    .foregroundStyle(ER.charcoal.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(retryTitle, action: retry)
                        .buttonStyle(GhostButtonStyle())
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Form fields

struct ERField<Content: View>: View {
    var label: String
    var hint: String? = nil
    var dark: Bool = false
    @ViewBuilder var content: Content

    init(_ label: String, hint: String? = nil, dark: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.dark = dark
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ERSectionHeader(text: label, dark: dark)
            content
            if let hint {
                ERNote(text: hint, dark: dark)
            }
        }
    }
}

extension StorefrontPilot: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let pane = pan.view else { return false }
        let move = pan.translation(in: pane)
        let flick = pan.velocity(in: pane)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

struct ERTextField: View {
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var dark: Bool = false

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(dark ? ER.cream.opacity(0.4) : ER.charcoal.opacity(0.35)))
            .font(.erBody)
            .foregroundStyle(dark ? ER.cream : ER.charcoal)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background { BeveledRect(radius: 10, cap: 12).fill(dark ? ER.darkCard : ER.card) }
            .overlay { BeveledRect(radius: 10, cap: 12).stroke(dark ? ER.orange : ER.charcoal, lineWidth: 2) }
    }
}

struct ERTextEditor: View {
    var placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.erBody)
                .foregroundStyle(ER.charcoal)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(minHeight: minHeight)
            if text.isEmpty {
                Text(placeholder)
                    .font(.erBody)
                    .foregroundStyle(ER.charcoal.opacity(0.35))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .background { BeveledRect(radius: 10, cap: 14).fill(ER.card) }
        .overlay { BeveledRect(radius: 10, cap: 14).stroke(ER.charcoal, lineWidth: 2) }
    }
}

struct ERTimeField: View {
    @Binding var minutes: Int
    var dark: Bool = false

    private var binding: Binding<Date> {
        Binding(
            get: { ERTime.date(fromMinutes: minutes) },
            set: { minutes = ERTime.minutes(from: $0) }
        )
    }

    var body: some View {
        DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(ER.scarlet)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

struct ERToggleRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var dark: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.erBodyBold)
                    .foregroundStyle(dark ? ER.cream : ER.charcoal)
                if let subtitle {
                    Text(subtitle)
                        .font(.erCaption)
                        .foregroundStyle(dark ? ER.cream.opacity(0.7) : ER.charcoal.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ER.scarlet)
        }
    }
}

/// A stepper built from the app's own parts.
struct ERStepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 5
    var suffix: String = "min"

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.erBodyBold)
                .foregroundStyle(ER.charcoal)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                ERIconButton(systemName: "minus") {
                    value = max(range.lowerBound, value - step)
                }
                Text("\(value) \(suffix)")
                    .font(.erHours)
                    .foregroundStyle(ER.charcoal)
                    .frame(minWidth: 74)
                ERIconButton(systemName: "plus") {
                    value = min(range.upperBound, value + step)
                }
            }
        }
    }
}

// MARK: - Navigation bar

struct ERNavBar: View {
    var title: String
    var dark: Bool = false
    var onBack: (() -> Void)? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let onBack {
                ERIconButton(systemName: "chevron.left", dark: dark, action: onBack)
            }
            Text(title.uppercased())
                .font(.erScreenTitleSmall)
                .tracking(-0.5)
                .foregroundStyle(.fire)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            if let trailing { trailing }
        }
    }
}

// MARK: - Screen scaffold

struct ERScreen<Content: View>: View {
    var dark: Bool = false
    var sparkSeed: Int = 3
    @ViewBuilder var content: Content

    init(dark: Bool = false, sparkSeed: Int = 3, @ViewBuilder content: () -> Content) {
        self.dark = dark
        self.sparkSeed = sparkSeed
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            (dark ? ER.cherry : ER.cream).ignoresSafeArea()
            // Only the strip behind the status bar, where no text of ours ever goes.
            SparkField(seed: sparkSeed, count: 4, bright: dark)
                .frame(height: 44)
                .padding(.horizontal, 10)
                .offset(y: -46)
                .ignoresSafeArea(edges: .top)
            content
        }
    }
}

// MARK: - Row helpers

struct ERKeyValueRow: View {
    var key: String
    var value: String
    var dark: Bool = false
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.erBody)
                .foregroundStyle(dark ? ER.cream.opacity(0.8) : ER.charcoal.opacity(0.75))
            Spacer(minLength: 6)
            Text(value)
                .font(mono ? .erHours : .erBodyBold)
                .foregroundStyle(dark ? ER.cream : ER.charcoal)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A tappable list row that keeps the card language.
struct ERNavRow: View {
    var title: String
    var detail: String? = nil
    var index: Int = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ERCard(index: index) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.erBodyBold)
                            .foregroundStyle(ER.charcoal)
                        if let detail {
                            Text(detail)
                                .font(.erCaption)
                                .foregroundStyle(ER.charcoal.opacity(0.65))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(ER.scarlet)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
