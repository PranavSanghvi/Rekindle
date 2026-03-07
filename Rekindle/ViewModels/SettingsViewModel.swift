import Foundation
import SwiftData

/// ViewModel for the Settings tab
@MainActor
@Observable
final class SettingsViewModel {

    var errorMessage: String?

    private var modelContext: ModelContext?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Get or create the singleton AppSettings
    func getOrCreateSettings() -> AppSettings? {
        guard let modelContext else { return nil }
        do {
            var descriptor = FetchDescriptor<AppSettings>()
            descriptor.fetchLimit = 1
            let existing = try modelContext.fetch(descriptor)
            if let settings = existing.first {
                return settings
            }
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            try modelContext.save()
            return newSettings
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
            return nil
        }
    }

    func save() {
        do {
            try modelContext?.save()
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }
}
