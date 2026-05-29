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

    /// Update notification content with actual contact names.
    func schedulePersonalizedNotification(
        contactNames: [String],
        settings: AppSettings
    ) async {
        await NotificationService.schedulePersonalized(
            names: contactNames,
            settings: settings,
            center: center
        )
    }

    /// Schedule (or replace) the personalized notification for its target day.
    ///
    /// To avoid firing two notifications at the same time, this reuses the SAME identifier as
    /// that weekday's recurring notification (`rekindle_day_N`). Adding a request with an existing
    /// identifier replaces it, so there is only ever ONE notification per weekday slot —
    /// personalized when names are available, generic otherwise. It repeats weekly to preserve
    /// cadence if the app isn't reopened; the next app launch (which resets to generic) or
    /// background run refreshes the content. Shared by the app and the background task.
    static func schedulePersonalized(
        names: [String],
        settings: AppSettings,
        center: UNUserNotificationCenter = .current()
    ) async {
        guard !names.isEmpty else { return }
        guard !settings.isCurrentlyPaused else { return }

        // Always check authorization fresh from the system.
        let authSettings = await center.notificationSettings()
        guard authSettings.authorizationStatus == .authorized else { return }

        var timeComponents = DateComponents()
        timeComponents.hour = settings.notificationHour
        timeComponents.minute = settings.notificationMinute

        let calendar = Calendar.current
        guard let targetDate = calendar.nextDate(
            after: Date(),
            matching: timeComponents,
            matchingPolicy: .nextTime
        ) else { return }

        // Only override a day we actually notify on.
        let weekday = calendar.component(.weekday, from: targetDate)
        guard settings.isDayScheduled(weekday) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rekindle 🔥"
        if names.count == 1 {
            content.body = "\(names[0]) — time to reconnect! 👋"
        } else {
            let others = names.count - 1
            content.body = "\(names[0]) and \(others) other\(others == 1 ? "" : "s") — time to reconnect! 👋"
        }
        content.sound = .default

        // Same weekly trigger as the generic notification, but personalized content.
        var triggerComponents = DateComponents()
        triggerComponents.weekday = weekday
        triggerComponents.hour = settings.notificationHour
        triggerComponents.minute = settings.notificationMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)

        // Reuse the weekday identifier so this REPLACES the generic one (no duplicate).
        // Also clear the legacy identifier so older installs don't keep a stray duplicate.
        let identifier = "rekindle_day_\(weekday)"
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier, "rekindle_personalized_today"]
        )

        let request = UNNotificationRequest(
            identifier: identifier,
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
