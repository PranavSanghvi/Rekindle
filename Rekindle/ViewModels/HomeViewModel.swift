import Foundation
import SwiftData
import SwiftUI
import WidgetKit

/// ViewModel for the Home tab — manages today's recommendations
@MainActor
@Observable
final class HomeViewModel {

    var todayRecommendations: [Recommendation] = []
    /// Favorite picks — a separate channel shown in addition to standard picks.
    var favoriteRecommendations: [Recommendation] = []
    var isLoading = false
    var showSnoozeFor: RekindleContact?
    var errorMessage: String?

    /// Tracks which recommendation the user tapped "Message" on (to prompt on return)
    var pendingMessageRecommendation: Recommendation?
    /// Controls the "Did you send it?" prompt
    var showReturnPrompt = false

    private var modelContext: ModelContext?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Load today's recommendations or generate new ones
    func loadToday(settings: AppSettings) {
        guard let modelContext else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Clean up any duplicate recs a widget/app generation race may have created.
            RecommendationEngine.deduplicateTodayRecommendations(modelContext: modelContext)

            let todayStart = Calendar.current.startOfDay(for: Date())
            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

            // First try to fetch existing STANDARD recommendations for today
            // (favorites are loaded separately, below — they must not appear here or
            // count toward the daily total).
            let descriptor = FetchDescriptor<Recommendation>(
                predicate: #Predicate<Recommendation> { rec in
                    rec.date >= todayStart && rec.date < todayEnd && rec.isFavorite == false
                },
                sortBy: [SortDescriptor(\.date)]
            )
            let existing = try modelContext.fetch(descriptor)

            if existing.isEmpty {
                // Generate new recommendations
                let newRecs = try RecommendationEngine.generateRecommendations(
                    modelContext: modelContext,
                    settings: settings
                )
                todayRecommendations = newRecs
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                todayRecommendations = existing
            }

            // Favorites — a separate channel, loaded/generated independently of standard picks
            if settings.favoritesEnabled && !settings.isCurrentlyPaused {
                let favDescriptor = FetchDescriptor<Recommendation>(
                    predicate: #Predicate<Recommendation> { rec in
                        rec.date >= todayStart && rec.date < todayEnd && rec.isFavorite == true
                    },
                    sortBy: [SortDescriptor(\.date)]
                )
                let existingFavorites = try modelContext.fetch(favDescriptor)
                if existingFavorites.isEmpty {
                    favoriteRecommendations = try RecommendationEngine.generateFavoriteRecommendations(
                        modelContext: modelContext,
                        settings: settings
                    )
                } else {
                    favoriteRecommendations = existingFavorites
                }
            } else {
                favoriteRecommendations = []
            }
        } catch {
            errorMessage = "Failed to load recommendations: \(error.localizedDescription)"
        }
    }

    // MARK: - Actions

    func markDone(_ recommendation: Recommendation) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.markDone(recommendation, modelContext: modelContext)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    func skip(_ recommendation: Recommendation) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.skip(recommendation, modelContext: modelContext)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    func postpone(_ recommendation: Recommendation) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.postpone(recommendation, modelContext: modelContext)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    func snoozeContact(_ contact: RekindleContact, until date: Date) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.snoozeContact(contact, until: date, modelContext: modelContext)
            // Mark the card with the correct snoozed status
            if let rec = todayRecommendations.first(where: { $0.contact === contact && $0.status == .pending }) {
                rec.status = .snoozed
                rec.actionDate = Date()
                try modelContext.save()
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Failed to snooze: \(error.localizedDescription)"
        }
    }

    func blockContact(_ contact: RekindleContact) {
        guard let modelContext else { return }
        contact.isBlocked = true
        contact.snoozedUntil = nil
        contact.isFavorite = false // blocking drops favorite status
        favoriteRecommendations.removeAll { $0.contact === contact }
        // Mark the card with the correct blocked status
        if let rec = todayRecommendations.first(where: { $0.contact === contact && $0.status == .pending }) {
            rec.status = .blocked
            rec.actionDate = Date()
        }
        do {
            try modelContext.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Failed to block: \(error.localizedDescription)"
        }
    }

    /// Open Messages app directly for a contact, track for return prompt
    func openMessages(for recommendation: Recommendation) {
        guard let contact = recommendation.contact,
              let phone = contact.phoneNumber else { return }

        pendingMessageRecommendation = recommendation
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)

        if let url = URL(string: "sms:\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    /// Start a phone call for a contact, tracking for the return prompt (used by favorites)
    func call(for recommendation: Recommendation) {
        guard let contact = recommendation.contact,
              let phone = contact.phoneNumber else { return }

        pendingMessageRecommendation = recommendation
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)

        if let url = URL(string: "tel:\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    /// Remove a contact from favorites (drops it from the favorites channel)
    func removeFavorite(_ contact: RekindleContact) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.removeFavorite(contact, modelContext: modelContext)
            favoriteRecommendations.removeAll { $0.contact === contact }
        } catch {
            errorMessage = "Failed to remove favorite: \(error.localizedDescription)"
        }
    }

    /// Called when app returns to foreground — show prompt if we left for Messages
    func handleReturnFromBackground() {
        if pendingMessageRecommendation != nil {
            showReturnPrompt = true
        }
    }

    /// User confirmed they sent the message from the return prompt
    func confirmSent() {
        if let rec = pendingMessageRecommendation {
            markDone(rec)
        }
        pendingMessageRecommendation = nil
        showReturnPrompt = false
    }

    /// User said "not yet" from the return prompt
    func dismissReturnPrompt() {
        pendingMessageRecommendation = nil
        showReturnPrompt = false
    }

    /// Generate more recommendations for today
    func getMorePicks(count: Int, settings: AppSettings) {
        guard let modelContext else { return }
        do {
            let newRecs = try RecommendationEngine.generateMoreRecommendations(
                count: count,
                modelContext: modelContext,
                settings: settings
            )
            todayRecommendations.append(contentsOf: newRecs)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Failed to get more picks: \(error.localizedDescription)"
        }
    }

    var pendingCount: Int {
        todayRecommendations.filter { $0.status == .pending }.count
    }

    var allResolved: Bool {
        !todayRecommendations.isEmpty && pendingCount == 0
    }
}
