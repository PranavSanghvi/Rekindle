import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct RekindleApp: App {
    @StateObject private var contactService = ContactService()
    @StateObject private var notificationService = NotificationService()

    var sharedModelContainer: ModelContainer = {
        let fileManager = FileManager.default

        // Migrate old database to App Group container if needed (one-time for existing users).
        // If the App Group is unavailable (missing/misspelled entitlement), skip migration —
        // SharedModelContainer.create() below surfaces a clear typed error instead of crashing here.
        if let appGroupURL = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupIdentifier) {
            let newStoreURL = appGroupURL.appendingPathComponent("Rekindle.store")

            if !fileManager.fileExists(atPath: newStoreURL.path) {
                // Check for old database in the default SwiftData location
                if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let oldStoreURL = appSupportURL.appendingPathComponent("default.store")
                    if fileManager.fileExists(atPath: oldStoreURL.path) {
                        try? fileManager.copyItem(at: oldStoreURL, to: newStoreURL)
                        // Also copy WAL and SHM files if they exist
                        let walURL = oldStoreURL.appendingPathExtension("wal")
                        let shmURL = oldStoreURL.appendingPathExtension("shm")
                        if fileManager.fileExists(atPath: walURL.path) {
                            try? fileManager.copyItem(at: walURL, to: newStoreURL.appendingPathExtension("wal"))
                        }
                        if fileManager.fileExists(atPath: shmURL.path) {
                            try? fileManager.copyItem(at: shmURL, to: newStoreURL.appendingPathExtension("shm"))
                        }
                    }
                }
            }
        }

        do {
            return try SharedModelContainer.create()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Register background task handler
        BackgroundTaskService.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(contactService)
                .environmentObject(notificationService)
                .preferredColorScheme(.light)
                .onAppear {
                    // Ensure AppSettings singleton exists
                    let context = sharedModelContainer.mainContext
                    let descriptor = FetchDescriptor<AppSettings>()
                    if let existing = try? context.fetch(descriptor), existing.isEmpty {
                        context.insert(AppSettings())
                        try? context.save()
                    }

                    // Expire old pending recommendations when app launches
                    BackgroundTaskService.expireOldRecommendations(modelContext: context)

                    // Schedule background refresh based on current settings
                    Task { @MainActor in
                        var settingsDescriptor = FetchDescriptor<AppSettings>()
                        settingsDescriptor.fetchLimit = 1
                        if let settings = try? context.fetch(settingsDescriptor).first {
                            BackgroundTaskService.scheduleBackgroundRefresh(settings: settings)
                            await notificationService.scheduleNotifications(settings: settings)
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
