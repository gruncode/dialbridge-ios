import SwiftUI
import UIKit
import UserNotifications

@main
struct BrowserDialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Registers with Apple's push service and handles a tapped notification.
///
/// SwiftUI has no hook for either, so the old delegate is still the way in.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestPermissionAndRegister()
        return true
    }

    /// Ask once, then register. Registration is what produces the device token
    /// that goes into the pairing code, so nothing works until this succeeds.
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // APNs hands back raw bytes; the relay addresses devices by their hex
        // form, which is what Apple's HTTP interface expects in the path.
        Pairing.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .pairingChanged, object: nil)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Usual causes: no push entitlement, or running in the simulator.
        Pairing.deviceToken = ""
        NotificationCenter.default.post(name: .pairingChanged, object: nil)
    }

    /// The user tapped the notification.
    ///
    /// This is where iOS differs most from Android. An iOS app cannot open a
    /// URL from the background, so the dialling cannot happen inside the
    /// extension — the tap has to bring the app forward first, and only then
    /// may it hand `tel:` to the system.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let info = response.notification.request.content.userInfo
        guard
            let number = info["number"] as? String,
            Crypto.looksLikePhoneNumber(number)
        else {
            return
        }
        Dialer.dial(number)
    }

    /// Show the alert even while the app is open, so a request is never missed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension Notification.Name {
    static let pairingChanged = Notification.Name("browserdial.pairingChanged")
}
