import Foundation
import UserNotifications
import WatchKit

/// Device token is held in memory, not cached on disk, per APNs guidance.
final class VoxiePushDelegate: NSObject, WKApplicationDelegate {
    var onToken: ((String) -> Void)? {
        didSet { if let deviceToken { onToken?(deviceToken) } }
    }
    private var deviceToken: String?

    func registerNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { allowed, _ in
            if allowed {
                DispatchQueue.main.async { WKApplication.shared().registerForRemoteNotifications() }
            }
        }
    }

    func didRegisterForRemoteNotifications(withDeviceToken token: Data) {
        let value = token.map { String(format: "%02x", $0) }.joined()
        deviceToken = value
        onToken?(value)
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        // APNs is optional. In-app friends and foreground audio remain usable.
    }
}
