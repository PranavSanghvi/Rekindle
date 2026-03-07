import Foundation
import SwiftData
import SwiftUI

/// ViewModel for the Home tab — manages today's recommendations
@MainActor
@Observable
final class HomeViewModel {

    var todayRecommendations: [Recommendation] = []
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
            let todayStart = Calendar.current.startOfDay(for: Date())
            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

            // First try to fetch existing recommendations for today
            let descriptor = FetchDescriptor<Recommendation>(
                predicate: #Predicate<Recommendation> { rec in
                    rec.date >= todayStart && rec.date < todayEnd
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
            } else {
                todayRecommendations = existing
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
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    func skip(_ recommendation: Recommendation) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.skip(recommendation, modelContext: modelContext)
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    func postpone(_ recommendation: Recommendation) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.postpone(recommendation, modelContext: modelContext)
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    func snoozeContact(_ contact: RekindleContact, until date: Date) {
        guard let modelContext else { return }
        do {
            try RecommendationEngine.snoozeContact(contact, until: date, modelContext: modelContext)
            // Also mark the recommendation for this contact as skipped so the card updates
            if let rec = todayRecommendations.first(where: { $0.contact === contact && $0.status == .pending }) {
                try RecommendationEngine.skip(rec, modelContext: modelContext)
            }
        } catch {
            errorMessage = "Failed to snooze: \(error.localizedDescription)"
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
