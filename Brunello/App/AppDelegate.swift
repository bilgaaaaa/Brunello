import OSLog
import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted when a push arrives, so the diary reloads right away.
    static let diaryDidChange = Notification.Name("diaryDidChange")
}

/// Receives the push token from iOS and decides how notifications show while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushService.saveDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.push.error("Push registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Shows the banner even when the app is open, and reloads the diary underneath it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(name: .diaryDidChange, object: nil)
        completionHandler([.banner, .list, .sound])
    }

    /// Tapping a notification opens the app; the diary reloads so the new entry is there.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .diaryDidChange, object: nil)
        completionHandler()
    }
}
