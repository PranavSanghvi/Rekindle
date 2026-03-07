import Foundation
import SwiftData

/// Which days to send recommendations
enum SchedulePreset: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekends = "Weekends"
    case custom = "Custom"
}

@Model
final class AppSettings {
    /// How many contacts to recommend per session
    var contactsPerSession: Int = 3

    /// Schedule preset
    var schedulePresetRawValue: String = SchedulePreset.daily.rawValue

    /// Custom days of the week (1=Sunday, 2=Monday, ... 7=Saturday)
    /// Stored as comma-separated string for SwiftData compatibility
    var customDaysString: String = ""

    /// Time of day for notifications (only hour/minute are used)
    var notificationHour: Int = 9
    var notificationMinute: Int = 0

    /// Cooldown in days before someone can be re-recommended
    var cooldownDays: Int = 90

    /// Whether recommendations are paused
    var isPaused: Bool = false

    /// If paused, auto-resume after this date
    var pausedUntil: Date?

    // MARK: - Computed Properties

    var schedulePreset: SchedulePreset {
        get { SchedulePreset(rawValue: schedulePresetRawValue) ?? .daily }
        set { schedulePresetRawValue = newValue.rawValue }
    }

    var customDays: Set<Int> {
        get {
            Set(customDaysString.split(separator: ",").compactMap { Int($0) })
        }
        set {
            customDaysString = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }

    /// Returns true if today is a scheduled day
    var isTodayScheduled: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return isDayScheduled(weekday)
    }

    /// Check if a given weekday number is scheduled
    func isDayScheduled(_ weekday: Int) -> Bool {
        switch schedulePreset {
        case .daily:
            return true
        case .weekdays:
            return (2...6).contains(weekday) // Monday-Friday
        case .weekends:
            return weekday == 1 || weekday == 7 // Sunday, Saturday
        case .custom:
            return customDays.contains(weekday)
        }
    }

    /// Whether the app is currently in a paused state
    var isCurrentlyPaused: Bool {
        guard isPaused else { return false }
        if let pausedUntil {
            return pausedUntil > Date()
        }
        return true // Paused indefinitely
    }

    init() {}
}
