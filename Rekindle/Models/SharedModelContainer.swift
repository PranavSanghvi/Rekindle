import SwiftData
import Foundation

/// Shared ModelContainer factory used by both the main app and the widget extension.
/// Both targets read/write to the same SwiftData store via the App Group container.
enum SharedModelContainerError: Error {
    case appGroupUnavailable
}

enum SharedModelContainer {
    static let appGroupIdentifier = "group.com.pranavsanghvi.rekindle"

    static func create() throws -> ModelContainer {
        let schema = Schema([
            RekindleContact.self,
            Recommendation.self,
            AppSettings.self,
        ])

        guard let groupContainer = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedModelContainerError.appGroupUnavailable
        }
        let storeURL = groupContainer.appendingPathComponent("Rekindle.store")

        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
