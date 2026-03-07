import Foundation
import SwiftData

/// ViewModel for the History tab
@MainActor
@Observable
final class HistoryViewModel {

    var recommendations: [Recommendation] = []
    var isLoading = false
    var errorMessage: String?

    private var modelContext: ModelContext?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadHistory() {
        guard let modelContext else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let descriptor = FetchDescriptor<Recommendation>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            recommendations = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Failed to load history: \(error.localizedDescription)"
        }
    }

    /// Group recommendations by day
    var groupedByDate: [(date: Date, recommendations: [Recommendation])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recommendations) { rec in
            calendar.startOfDay(for: rec.date)
        }
        return grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, recommendations: $0.value) }
    }
}
