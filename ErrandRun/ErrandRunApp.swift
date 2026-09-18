//
//  ErrandRunApp.swift
//  ErrandRun
//

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

@main
struct ErrandRunApp: App {
    @StateObject private var store: AppStore
    @StateObject private var auth: AuthStore
    @StateObject private var sync: SyncEngine
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        let store = AppStore()
        let auth = AuthStore(store: store)
        let sync = SyncEngine(store: store)

        _store = StateObject(wrappedValue: store)
        _auth = StateObject(wrappedValue: auth)
        _sync = StateObject(wrappedValue: sync)

        sync.attach()
        auth.onSignedIn = { [weak sync] _ in
            sync?.enable()
            Task { await sync?.syncNow(fullPull: true) }
        }
        auth.onSignedOut = { [weak sync] in
            sync?.disable()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(sync)
                .tint(ER.scarlet)
                .task {
                    guard AppMode.isConnected else { return }

                    // The first request the app makes. It needs no account, so the
                    // X-App-Target header arrives whether or not anyone is signed in.
                    await AppTarget.shared.start()

                    // A session restored from the Keychain starts syncing straight away.
                    if await APIClient.shared.currentSession() != nil {
                        sync.enable()
                    }
                }
        }
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    private var trunk: [AnyHashable: Any] = [:]
    private var branch: [AnyHashable: Any] = [:]
    private var linger: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Ledger.relayKey
        sdk.appleAppID = Ledger.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            note(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(stirred), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Slip.fcm)
            UserDefaults.standard.set(token, forKey: Slip.push)
            UserDefaults(suiteName: Ledger.suite)?.set(token, forKey: Slip.sharedFcm)
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    private func note(_ payload: [AnyHashable: Any]) {
        var jotted: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            jotted = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            jotted = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            jotted = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            jotted = url
        }
        guard let link = jotted else { return }

        UserDefaults.standard.set(link, forKey: Slip.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .buzzed, object: nil, userInfo: ["temp_url": link])
        }
    }

    @objc private func stirred() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Slip.attStatus)
            }
        }
    }

    private func dawdle() {
        linger?.cancel()
        linger = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run { self?.stitch() }
        }
    }

    private func stitch() {
        linger?.cancel()
        linger = nil
        var bundle = trunk
        for (key, value) in branch {
            let tag = "deep_\(key)"
            if bundle[tag] == nil { bundle[tag] = value }
        }
        NotificationCenter.default.post(name: .paged, object: nil, userInfo: ["conversionData": bundle])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        note(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        note(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        note(userInfo)
        completionHandler(.newData)
    }
    
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        trunk = conversionInfo
        dawdle()
        if branch.isEmpty == false { stitch() }
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Slip.primed) == false else { return }
        branch = deepLink.clickEvent
        NotificationCenter.default.post(name: .pinned, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        linger?.cancel()
        linger = nil
        if trunk.isEmpty == false { stitch() }
    }
}
