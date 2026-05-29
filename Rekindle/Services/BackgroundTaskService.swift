import Foundation
import BackgroundTasks
import SwiftData
import UserNotifications
import WidgetKit

/// Manages background app refresh tasks for generating recommendations
@MainActor
final class BackgroundTaskService {

    static let taskIdentifier = "com.rekindle.app.generateRecommendations"

    /// The hour/minute to pre-generate recommendations: 15 minutes before the notification time.
    /// Borrows from the hour (and wraps across midnight) so e.g. 10:05 → 09:50 and 00:05 → 23:50,
    /// rather than clamping the minute to 0.
    private static func refreshTime(for settings: AppSettings) -> (hour: Int, minute: Int) {
        let total = settings.notificationHour * 60 + settings.notificationMinute - 15
        let normalized = ((total % 1440) + 1440) % 1440
        return (normalized / 60, normalized % 60)
    }

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
        let refresh = refreshTime(for: settings)
        var targetComponents = DateComponents()
        targetComponents.hour = refresh.hour
        targetComponents.minute = refresh.minute

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
                let refresh = refreshTime(for: settings)
                var targetComponents = calendar.dateComponents([.year, .month, .day], from: checkDate)
                targetComponents.hour = refresh.hour
                targetComponents.minute = refresh.minute

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
        // Create a fresh model context backed by the shared App Group store
        do {
            let container = try SharedModelContainer.create()
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

            // 1b. Clean up any duplicate recs a widget/app generation race may have created
            RecommendationEngine.deduplicateTodayRecommendations(modelContext: context)

            // 2. Ensure today's recommendations exist (no-op if the widget/app already seeded them)
            _ = try RecommendationEngine.generateRecommendations(
                modelContext: context,
                settings: settings
            )

            // 3. Schedule personalized notification with names.
            // Personalize from ALL of today's still-pending recs — whether this task generated
            // them or the widget/app seeded them first — so widget pre-seeding can't suppress
            // personalization. Reuses the weekday notification identifier so it REPLACES the
            // generic one for that day rather than firing a second notification at the same time.
            let todayStart = Calendar.current.startOfDay(for: Date())
            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
            let pendingRaw = RecommendationStatus.pending.rawValue
            let todayDescriptor = FetchDescriptor<Recommendation>(
                predicate: #Predicate<Recommendation> { rec in
                    rec.date >= todayStart && rec.date < todayEnd && rec.statusRawValue == pendingRaw
                },
                sortBy: [SortDescriptor(\.date)]
            )
            let todaysPending = (try? context.fetch(todayDescriptor)) ?? []
            if !todaysPending.isEmpty {
                let names = todaysPending.compactMap { $0.contact?.firstName }
                await NotificationService.schedulePersonalized(names: names, settings: settings)
            }

            // 4. Refresh the widget
            WidgetCenter.shared.reloadAllTimelines()

            // 5. Schedule next background refresh
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

}
