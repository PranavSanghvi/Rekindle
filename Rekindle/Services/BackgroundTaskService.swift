import Foundation
import BackgroundTasks
import SwiftData
import UserNotifications

/// Manages background app refresh tasks for generating recommendations
@MainActor
final class BackgroundTaskService {

    static let taskIdentifier = "com.rekindle.app.generateRecommendations"

    /// Register the background task with the system
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await handleBackgroundRefresh(refreshTask)
            }
        }
    }

    /// Schedule a background refresh to run before the notification time
    static func scheduleBackgroundRefresh(settings: AppSettings) {
        // Cancel any existing scheduled task
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

        guard !settings.isCurrentlyPaused else { return }

        // Schedule for 15 minutes before notification time
        let calendar = Calendar.current
        var targetComponents = DateComponents()
        targetComponents.hour = settings.notificationHour
        targetComponents.minute = max(0, settings.notificationMinute - 15)

        // Find the next scheduled day's time
        guard let nextDate = calendar.nextDate(
            after: Date(),
            matching: targetComponents,
            matchingPolicy: .nextTime
        ) else { return }

        // Only schedule if it's a scheduled day
        let weekday = calendar.component(.weekday, from: nextDate)
        guard settings.isDayScheduled(weekday) else {
            // Try to find the next valid scheduled day
            scheduleForNextValidDay(settings: settings)
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextDate

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }

    /// Find the next valid scheduled day and schedule for it
    private static func scheduleForNextValidDay(settings: AppSettings) {
        let calendar = Calendar.current
        var checkDate = Date()

        // Look up to 7 days ahead
        for _ in 0..<7 {
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let weekday = calendar.component(.weekday, from: checkDate)

            if settings.isDayScheduled(weekday) {
                var targetComponents = calendar.dateComponents([.year, .month, .day], from: checkDate)
                targetComponents.hour = settings.notificationHour
                targetComponents.minute = max(0, settings.notificationMinute - 15)

                guard let targetDate = calendar.date(from: targetComponents) else { continue }

                let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
                request.earliestBeginDate = targetDate

                do {
                    try BGTaskScheduler.shared.submit(request)
                } catch {
                    print("Failed to schedule background refresh: \(error)")
                }
                return
            }
        }
    }

    /// Handle the background refresh — generate recommendations + personalized notification
    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        // Create a fresh model context for background work
        do {
            let schema = Schema([
                RekindleContact.self,
                Recommendation.self,
                AppSettings.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            // Fetch settings
            var settingsDescriptor = FetchDescriptor<AppSettings>()
            settingsDescriptor.fetchLimit = 1
            guard let settings = try context.fetch(settingsDescriptor).first else {
                task.setTaskCompleted(success: false)
                return
            }

            // 1. Expire old pending recommendations
            expireOldRecommendations(modelContext: context)

            // 2. Generate today's recommendations
            let recommendations = try RecommendationEngine.generateRecommendations(
                modelContext: context,
                settings: settings
            )

            // 3. Schedule personalized notification with names
            if !recommendations.isEmpty {
                let names = recommendations.compactMap { $0.contact?.firstName }
                await schedulePersonalizedNotification(names: names, settings: settings)
            }

            // 4. Schedule next background refresh
            scheduleBackgroundRefresh(settings: settings)

            task.setTaskCompleted(success: true)
        } catch {
            print("Background refresh failed: \(error)")
            task.setTaskCompleted(success: false)
        }
    }

    /// Mark old pending recommendations as expired
    static func expireOldRecommendations(modelContext: ModelContext) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let pendingRaw = RecommendationStatus.pending.rawValue

        do {
            let descriptor = FetchDescriptor<Recommendation>(
                predicate: #Predicate<Recommendation> { rec in
                    rec.date < todayStart && rec.statusRawValue == pendingRaw
                }
            )
            let oldPending = try modelContext.fetch(descriptor)
            for rec in oldPending {
                rec.status = .expired
                rec.actionDate = todayStart
            }
            if !oldPending.isEmpty {
                try modelContext.save()
            }
        } catch {
            print("Failed to expire old recommendations: \(error)")
        }
    }

    /// Schedule a personalized notification with contact names
    private static func schedulePersonalizedNotification(
        names: [String],
        settings: AppSettings
    ) async {
        let center = UNUserNotificationCenter.current()
        let authSettings = await center.notificationSettings()
        guard authSettings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rekindle 🔥"

        if names.count == 1 {
            content.body = "\(names[0]) — time to reconnect! 👋"
        } else {
            let others = names.count - 1
            content.body = "\(names[0]) and \(others) other\(others == 1 ? "" : "s") — time to reconnect! 👋"
        }
        content.sound = .default

        // Schedule for the notification time
        var dateComponents = DateComponents()
        dateComponents.hour = settings.notificationHour
        dateComponents.minute = settings.notificationMinute

        let calendar = Calendar.current
        guard let targetDate = calendar.nextDate(
            after: Date(),
            matching: dateComponents,
            matchingPolicy: .nextTime
        ) else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: targetDate
            ),
            repeats: false
        )

        // Remove existing personalized notification
        center.removePendingNotificationRequests(
            withIdentifiers: ["rekindle_personalized_today"]
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
}
