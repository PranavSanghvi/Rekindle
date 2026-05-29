import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var contactService: ContactService
    @EnvironmentObject private var notificationService: NotificationService

    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Today", systemImage: "flame.fill")
                }
                .tag(0)

            ContactsListView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2.fill")
                }
                .tag(1)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(Theme.coral)
        .onAppear {
            configureTabBarAppearance()
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && contactService.authorizationStatus == .authorized {
                Task {
                    try? await contactService.importContacts(modelContext: modelContext)
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject private var contactService: ContactService
    @EnvironmentObject private var notificationService: NotificationService
    @Environment(\.modelContext) private var modelContext
    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var isImporting = false

    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                contactsPage.tag(1)
                notificationsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Theme.springAnimation, value: currentPage)

            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Theme.coral : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentPage ? 1.2 : 1.0)
                        .animation(Theme.springAnimation, value: currentPage)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Theme.dynamicAppBackground)
        .interactiveDismissDisabled()
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🔥")
                .font(.system(size: 80))

            Text("Welcome to Rekindle")
                .font(Theme.largeTitle)
                .multilineTextAlignment(.center)

            Text("Stay connected with the people who matter most. We'll remind you to reach out so no friendship fades away.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                HStack {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(GradientPillButtonStyle())
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 1: Contacts Permission

    private var contactsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("📇")
                .font(.system(size: 80))

            Text("Import Your Contacts")
                .font(Theme.title)

            Text("We request access to your contacts to suggest people to reconnect with. We'll never modify or share them.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        let granted = await contactService.requestAccess()
                        if granted {
                            isImporting = true
                            try? await contactService.importContacts(modelContext: modelContext)
                            isImporting = false
                        }
                        withAnimation { currentPage = 2 }
                    }
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                        Text("Continue")
                    }
                }
                .buttonStyle(GradientPillButtonStyle())
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 2: Notifications Permission

    private var notificationsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🔔")
                .font(.system(size: 80))

            Text("Stay on Track")
                .font(Theme.title)

            Text("Get a daily reminder with your personalized picks. You choose when and how often.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        _ = await notificationService.requestAuthorization()
                        
                        // Immediately schedule the default notifications now that we have permission
                        var descriptor = FetchDescriptor<AppSettings>()
                        descriptor.fetchLimit = 1
                        if let settings = try? modelContext.fetch(descriptor).first {
                            await notificationService.scheduleNotifications(settings: settings)
                            BackgroundTaskService.scheduleBackgroundRefresh(settings: settings)
                            
                            // Immediately queue up the personalized notification for today's recommendations
                            // (If the time has passed, it will automatically schedule for tomorrow at the same time)
                            let todayStart = Calendar.current.startOfDay(for: Date())
                            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
                            
                            let recDescriptor = FetchDescriptor<Recommendation>(
                                predicate: #Predicate<Recommendation> { rec in
                                    rec.date >= todayStart && rec.date < todayEnd
                                }
                            )
                            if let recs = try? modelContext.fetch(recDescriptor), !recs.isEmpty {
                                let names = recs.compactMap { $0.contact?.firstName }
                                await notificationService.schedulePersonalizedNotification(contactNames: names, settings: settings)
                            }
                        }

                        withAnimation(Theme.springAnimation) {
                            onComplete()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Continue")
                    }
                }
                .buttonStyle(GradientPillButtonStyle())
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helpers

    private func nextButton(page: Int) -> some View {
        Button {
            withAnimation { currentPage = page }
        } label: {
            HStack {
                Text("Next")
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(GradientPillButtonStyle())
    }

    private func actionRow(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.headline)
                Text(description)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.coral)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.headline)
                Text(detail)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
