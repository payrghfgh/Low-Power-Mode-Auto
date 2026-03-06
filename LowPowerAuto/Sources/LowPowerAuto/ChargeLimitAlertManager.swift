import Foundation
import UserNotifications
import AppKit

@MainActor
final class ChargeLimitAlertManager {
    private var didRequestPermissions = false

    func prepare() {
        guard !didRequestPermissions else { return }
        didRequestPermissions = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func refreshAuthorizationStatus() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
    }

    func notifyChargeLimitReached(limit: Int, current: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Charge Limit Reached"
        content.body = "Battery is at \(current)%. Unplug charger to hold around \(limit)%"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lowpowerauto.chargeLimitReached",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["lowpowerauto.chargeLimitReached"])
        UNUserNotificationCenter.current().add(request)
        NSSound.beep()
    }
}
