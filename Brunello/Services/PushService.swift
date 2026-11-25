import OSLog
import UIKit
import UserNotifications

/// Asks for notification permission and keeps this phone's push token on the server.
@MainActor
enum PushService {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows the system permission question (only the first time) and registers for pushes when allowed.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            let isGranted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            Logger.push.info("Notification permission granted: \(isGranted)")
            if isGranted { UIApplication.shared.registerForRemoteNotifications() }
            return isGranted
        } catch {
            Logger.push.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Refreshes the push token on every launch, without asking anything.
    static func registerIfAuthorized() async {
        guard await status() == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func saveDeviceToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        do {
            try await DiaryService.shared.saveDeviceToken(token, environment: environment)
            Logger.push.info("Push token saved (\(environment, privacy: .public))")
        } catch {
            Logger.push.error("Could not save the push token: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Xcode builds talk to Apple's sandbox push servers; TestFlight and App Store builds use production.
    private static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
