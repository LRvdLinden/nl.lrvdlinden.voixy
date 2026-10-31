import Foundation
import UserNotifications
import WatchKit

/// APNs registration and notification handling for the independent Watch app.
///
/// - Voxie open (foreground): a "praat met je" alert is not shown as a banner;
///   the audio is fetched and played right away instead.
/// - Voxie closed or in the background: watchOS shows the alert with sound and
///   haptic. Tapping it opens Voxie, which immediately plays the message
///   (unplayed audio stays on the server for two minutes).
final class VoxiePushDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Hex device token, delivered on the main queue. Kept in memory only.
    static var onToken: ((String) -> Void)? {
        didSet { if let latestToken { onToken?(latestToken) } }
    }
    /// Sender ID of a talk notification. `opened` is true when the user tapped it.
    static var onTalk: ((_ senderID: String?, _ opened: Bool) -> Void)? {
        didSet {
            if let pending = pendingOpen {
                pendingOpen = nil
                onTalk?(pending.isEmpty ? nil : pending, true)
            }
        }
    }
    private static var latestToken: String?
    private static var pendingOpen: String?

    func applicationDidFinishLaunching() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let listen = UNNotificationAction(identifier: "VOXIE_LISTEN", title: "Luister",
                                          options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "VOXIE_TALK", actions: [listen],
                                   intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // Register even without alert permission: the token is still useful
            // and the user may allow notifications later in Settings.
            DispatchQueue.main.async { WKApplication.shared().registerForRemoteNotifications() }
        }
    }

    func applicationDidBecomeActive() {
        WKApplication.shared().registerForRemoteNotifications()
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let value = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            Self.latestToken = value
            Self.onToken?(value)
        }
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        // Most often: missing Push Notifications capability / aps-environment.
        print("Voxie APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        if info["kind"] as? String == "talk" {
            // Voxie is on screen: play instead of showing a banner.
            let sender = info["sender"] as? String
            DispatchQueue.main.async { Self.onTalk?(sender, false) }
            completionHandler([])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let sender = info["sender"] as? String
        DispatchQueue.main.async {
            if let handler = Self.onTalk { handler(sender, true) } else { Self.pendingOpen = sender ?? "" }
        }
        completionHandler()
    }
}
