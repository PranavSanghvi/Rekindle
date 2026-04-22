import Foundation
import UserNotifications
import SwiftData

/// Manages local notification scheduling for Rekindle
@MainActor
final class NotificationService: ObservableObject {

    @Published var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    init() {
        Task { await checkAuthorization() }
    }

    // MARK: - Authorization

    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            return granted
        } catch {
            print("Notification auth failed: \(error)")
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedule recurring notifications based on app settings
    func scheduleNotifications(settings: AppSettings) async {
        guard !settings.isCurrentlyPaused else { return }

        // Always check authorization fresh from the system to avoid race conditions
        // with the async checkAuthorization() fired during init()
        let currentSettings = await center.notificationSettings()
        guard currentSettings.authorizationStatus == .authorized else { return }
        isAuthorized = true

        // Only remove existing notifications AFTER confirming we're authorized
        // and about to reschedule — otherwise we silently wipe everything
        center.removeAllPendingNotificationRequests()

        // Determine which days to schedule
        let scheduledDays: [Int]
        switch settings.schedulePreset {
        case .daily:
            scheduledDays = [1, 2, 3, 4, 5, 6, 7]
        case .weekdays:
            scheduledDays = [2, 3, 4, 5, 6]
        case .weekends:
            scheduledDays = [1, 7]
        case .custom:
            scheduledDays = Array(settings.customDays).sorted()
        }

        // Create a notification request for each scheduled day
        for weekday in scheduledDays {
            var dateComponents = DateComponents()
            dateComponents.weekday = weekday
            dateComponents.hour = settings.notificationHour
            dateComponents.minute = settings.notificationMinute

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )

            let content = UNMutableNotificationContent()
            content.title = "Rekindle 🔥"
            content.body = "Your daily picks are ready — time to reconnect!"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "rekindle_day_\(weekday)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                print("Failed to schedule notification for day \(weekday): \(error)")
            }
        }
    }

    /// Update notification content with actual contact names
    func schedulePersonalizedNotification(
        contactNames: [String],
        settings: AppSettings
    ) async {
        guard isAuthorized else { return }

        // Remove any existing personalized notification
        center.removePendingNotificationRequests(
            withIdentifiers: ["rekindle_personalized_today"]
        )

        guard !contactNames.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rekindle 🔥"

        if contactNames.count == 1 {
            content.body = "\(contactNames[0]) — time to reconnect! 👋"
        } else {
            let others = contactNames.count - 1
            content.body = "\(contactNames[0]) and \(others) other\(others == 1 ? "" : "s") — time to reconnect! 👋"
        }
        content.sound = .default

        // Schedule for the set time today if it hasn't passed, otherwise tomorrow
        var dateComponents = DateComponents()
        dateComponents.hour = settings.notificationHour
        dateComponents.minute = settings.notificationMinute

        let now = Date()
        let calendar = Calendar.current
        let targetDate = calendar.nextDate(
            after: now,
            matching: dateComponents,
            matchingPolicy: .nextTime
        ) ?? now

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "rekindle_personalized_today",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule personalized notification: \(error)")
        }
    }

    /// Cancel all pending notifications
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
