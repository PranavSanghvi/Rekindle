import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct RekindleApp: App {
    @StateObject private var contactService = ContactService()
    @StateObject private var notificationService = NotificationService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RekindleContact.self,
            Recommendation.self,
            AppSettings.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
