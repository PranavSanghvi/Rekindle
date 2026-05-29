import Foundation
import SwiftData

/// Weighted random selection engine with cooldown logic
struct RecommendationEngine {

    /// Generate daily recommendations based on current settings
    @MainActor
    static func generateRecommendations(
        modelContext: ModelContext,
        settings: AppSettings
    ) throws -> [Recommendation] {
        // Don't generate if paused
        guard !settings.isCurrentlyPaused else { return [] }

        // Don't generate if today isn't a scheduled day
        guard settings.isTodayScheduled else { return [] }

        // Check if we already generated for today
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

        var existingDescriptor = FetchDescriptor<Recommendation>(
            predicate: #Predicate<Recommendation> { rec in
                rec.date >= todayStart && rec.date < todayEnd
            }
        )
        existingDescriptor.fetchLimit = 1
        let existingToday = try modelContext.fetch(existingDescriptor)
        if !existingToday.isEmpty { return [] }

        // Fetch eligible contacts
        let allContactsDescriptor = FetchDescriptor<RekindleContact>()
        let allContacts = try modelContext.fetch(allContactsDescriptor)

        let now = Date()
        let cooldownInterval = TimeInterval(settings.cooldownDays * 86400)

        let eligibleContacts = allContacts.filter { contact in
            // Must not be blocked
            guard !contact.isBlocked else { return false }

            // Must not be snoozed
            if let snoozedUntil = contact.snoozedUntil, snoozedUntil > now {
                return false
            }

            // Must not be in cooldown
            if let lastContacted = contact.lastContactedDate {
                if now.timeIntervalSince(lastContacted) < cooldownInterval {
                    return false
                }
            }

            return true
        }

        guard !eligibleContacts.isEmpty else { return [] }

        // Weighted random selection
        let selected = weightedRandomSample(
            from: eligibleContacts,
            count: min(settings.contactsPerSession, eligibleContacts.count)
        )

        // Create recommendations
        var recommendations: [Recommendation] = []
        for contact in selected {
            let rec = Recommendation(contact: contact, date: now)
            contact.lastRecommendedDate = now
            modelContext.insert(rec)
            recommendations.append(rec)
        }

        try modelContext.save()
        return recommendations
    }

    /// Generate additional recommendations on top of today's existing ones
    @MainActor
    static func generateMoreRecommendations(
        count: Int,
        modelContext: ModelContext,
        settings: AppSettings
    ) throws -> [Recommendation] {
        // Fetch today's already-recommended contact IDs
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

        let todayDescriptor = FetchDescriptor<Recommendation>(
            predicate: #Predicate<Recommendation> { rec in
                rec.date >= todayStart && rec.date < todayEnd
            }
        )
        let todayRecs = try modelContext.fetch(todayDescriptor)
        let alreadyRecommendedIDs = Set(todayRecs.compactMap { $0.contact?.contactIdentifier })

        // Fetch all contacts and filter
        let allContactsDescriptor = FetchDescriptor<RekindleContact>()
        let allContacts = try modelContext.fetch(allContactsDescriptor)

        let now = Date()
        let cooldownInterval = TimeInterval(settings.cooldownDays * 86400)

        let eligibleContacts = allContacts.filter { contact in
            guard !contact.isBlocked else { return false }
            if let snoozedUntil = contact.snoozedUntil, snoozedUntil > now { return false }
            if let lastContacted = contact.lastContactedDate {
                if now.timeIntervalSince(lastContacted) < cooldownInterval { return false }
            }
            // Exclude already recommended today
            if alreadyRecommendedIDs.contains(contact.contactIdentifier) { return false }
            return true
        }

        guard !eligibleContacts.isEmpty else { return [] }

        let selected = weightedRandomSample(
            from: eligibleContacts,
            count: min(count, eligibleContacts.count)
        )

        var recommendations: [Recommendation] = []
        for contact in selected {
            let rec = Recommendation(contact: contact, date: now)
            contact.lastRecommendedDate = now
            modelContext.insert(rec)
            recommendations.append(rec)
        }

        try modelContext.save()
        return recommendations
    }

    /// Weighted random sample — contacts not reached out to in longer get higher weight
    private static func weightedRandomSample(
        from contacts: [RekindleContact],
        count: Int
    ) -> [RekindleContact] {
        let now = Date()

        // Calculate weights based on days since last contact
        let weights: [(contact: RekindleContact, weight: Double)] = contacts.map { contact in
            let daysSince: Double
            if let lastContacted = contact.lastContactedDate {
                daysSince = max(1, now.timeIntervalSince(lastContacted) / 86400)
            } else if let lastRecommended = contact.lastRecommendedDate {
                // Never contacted but was recommended before
                daysSince = max(1, now.timeIntervalSince(lastRecommended) / 86400) * 0.8
            } else {
                // Never contacted, never recommended — use time since import
                daysSince = max(1, now.timeIntervalSince(contact.importedDate) / 86400)
            }
            // Use square root to avoid extreme weights for very old contacts
            return (contact, sqrt(daysSince))
        }

        var selected: [RekindleContact] = []
        var remaining = weights
        var totalWeight = remaining.reduce(0) { $0 + $1.weight }

        for _ in 0..<count {
            guard !remaining.isEmpty else { break }

            // Weighted random pick
            var random = Double.random(in: 0..<totalWeight)
            var pickedIndex = 0

            for (index, item) in remaining.enumerated() {
                random -= item.weight
                if random <= 0 {
                    pickedIndex = index
                    break
                }
            }

            selected.append(remaining[pickedIndex].contact)
            totalWeight -= remaining[pickedIndex].weight
            remaining.remove(at: pickedIndex)
        }

        return selected
    }

    /// Remove duplicate recommendations for the same contact on the same day.
    ///
    /// The widget can seed today's recommendations on first load (before the app or background
    /// task has run). If the widget and the app both observe an empty day at the same instant,
    /// a cross-process race can insert two sets of recommendations. This self-heals that: it keeps
    /// one recommendation per contact for today — preferring any the user has already acted on —
    /// and deletes the rest. Safe to call repeatedly; runs only in the app and background task
    /// (single-writer contexts that never execute concurrently).
    @MainActor
    static func deduplicateTodayRecommendations(modelContext: ModelContext) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

        do {
            let descriptor = FetchDescriptor<Recommendation>(
                predicate: #Predicate<Recommendation> { rec in
                    rec.date >= todayStart && rec.date < todayEnd
                },
                sortBy: [SortDescriptor(\.date)]
            )
            let todays = try modelContext.fetch(descriptor)

            var kept: [String: Recommendation] = [:]
            var toDelete: [Recommendation] = []

            for rec in todays {
                guard let id = rec.contact?.contactIdentifier else { continue }
                guard let existing = kept[id] else {
                    kept[id] = rec
                    continue
                }
                // Prefer a recommendation the user has already acted on so we never drop their action.
                if rec.actionDate != nil && existing.actionDate == nil {
                    kept[id] = rec
                    toDelete.append(existing)
                } else {
                    toDelete.append(rec)
                }
            }

            if !toDelete.isEmpty {
                for rec in toDelete { modelContext.delete(rec) }
                try modelContext.save()
            }
        } catch {
            print("Failed to deduplicate recommendations: \(error)")
        }
    }

    // MARK: - Actions

    /// Mark a recommendation as done — starts cooldown
    @MainActor
    static func markDone(_ recommendation: Recommendation, modelContext: ModelContext) throws {
        recommendation.status = .done
        recommendation.actionDate = Date()
        recommendation.contact?.lastContactedDate = Date()
        try modelContext.save()
    }

    /// Skip a recommendation — no cooldown
    @MainActor
    static func skip(_ recommendation: Recommendation, modelContext: ModelContext) throws {
        recommendation.status = .skipped
        recommendation.actionDate = Date()
        try modelContext.save()
    }

    /// Postpone — put back in eligible pool for next time
    @MainActor
    static func postpone(_ recommendation: Recommendation, modelContext: ModelContext) throws {
        recommendation.status = .postponed
        recommendation.actionDate = Date()
        try modelContext.save()
    }

    /// Snooze a contact for a given duration
    @MainActor
    static func snoozeContact(
        _ contact: RekindleContact,
        until date: Date,
        modelContext: ModelContext
    ) throws {
        contact.snoozedUntil = date
        try modelContext.save()
    }
}
