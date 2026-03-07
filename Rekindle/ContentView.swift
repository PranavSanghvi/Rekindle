import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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

    private let totalPages = 7

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                contactsPage.tag(1)
                notificationsPage.tag(2)
                howItWorksPage.tag(3)
                actionsPage.tag(4)
                schedulePage.tag(5)
                readyPage.tag(6)
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
        .interactiveDismissDisabled()
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "flame.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.warmGradient)

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
            .buttonStyle(GradientButtonStyle())
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 1: Contacts Permission

    private var contactsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 70))
                .foregroundStyle(Theme.warmGradient)

            Text("Import Your Contacts")
                .font(Theme.title)

            Text("We need access to your contacts to suggest people to reconnect with. We'll never modify or share them.")
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
                        Text("Allow Access")
                    }
                }
                .buttonStyle(GradientButtonStyle())

                Button("Skip for Now") {
                    withAnimation { currentPage = 2 }
                }
                .font(Theme.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 2: Notifications Permission

    private var notificationsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 70))
                .foregroundStyle(Theme.warmGradient)

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
                        withAnimation { currentPage = 3 }
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Enable Notifications")
                    }
                }
                .buttonStyle(GradientButtonStyle())

                Button("Skip for Now") {
                    withAnimation { currentPage = 3 }
                }
                .font(Theme.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Page 3: How It Works

    private var howItWorksPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Mock card illustration
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.coral.gradient)
                            .frame(width: 44, height: 44)
                        Text("SJ")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sarah Johnson")
                            .font(Theme.headline)
                        Text("Haven't connected in a while")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "message.fill")
                        .foregroundStyle(Theme.coral)
                }
                .padding(Theme.paddingMedium)
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 8, y: 4)
            .padding(.horizontal, 40)

            Text("How It Works")
                .font(Theme.title)

            Text("Each day, we randomly pick a few contacts for you to reconnect with. People you haven't reached out to in a while are more likely to be selected.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            nextButton(page: 4)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Page 4: Your Actions

    private var actionsPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Your Actions")
                .font(Theme.title)

            Text("Here's what you can do with each pick:")
                .font(Theme.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                actionRow(
                    icon: "hand.draw.fill",
                    iconColor: Theme.done,
                    title: "Swipe Right",
                    description: "Mark as sent — the quickest way!"
                )
                actionRow(
                    icon: "checkmark.circle.fill",
                    iconColor: Theme.done,
                    title: "Done",
                    description: "I reached out! Starts the cooldown timer."
                )
                actionRow(
                    icon: "message.fill",
                    iconColor: Theme.coral,
                    title: "Message",
                    description: "Opens iMessage directly for that person."
                )
                actionRow(
                    icon: "forward.fill",
                    iconColor: .secondary,
                    title: "Skip",
                    description: "Not today — no cooldown, they stay in the pool."
                )
                actionRow(
                    icon: "clock.arrow.circlepath",
                    iconColor: Theme.postponed,
                    title: "Postpone",
                    description: "Maybe next time — back in the pool for the next cycle."
                )
                actionRow(
                    icon: "moon.zzz.fill",
                    iconColor: Theme.softTeal,
                    title: "Snooze",
                    description: "Hide this person for weeks or months."
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            nextButton(page: 5)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Page 5: Customize Schedule

    private var schedulePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 70))
                .foregroundStyle(Theme.warmGradient)

            Text("Make It Yours")
                .font(Theme.title)

            VStack(alignment: .leading, spacing: 16) {
                scheduleRow(
                    icon: "calendar",
                    title: "Frequency",
                    detail: "Daily, weekdays, weekends, or custom days"
                )
                scheduleRow(
                    icon: "person.2",
                    title: "Contacts Per Day",
                    detail: "Choose 1 to 20 picks per session"
                )
                scheduleRow(
                    icon: "clock",
                    title: "Notification Time",
                    detail: "Pick the perfect time to be reminded"
                )
                scheduleRow(
                    icon: "arrow.counterclockwise",
                    title: "Cooldown",
                    detail: "How long before someone is suggested again"
                )
            }
            .padding(.horizontal, 32)

            Text("You can adjust all of this in Settings anytime.")
                .font(Theme.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            nextButton(page: 6)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Page 6: Ready

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("You're All Set! 🎉")
                .font(Theme.largeTitle)
                .multilineTextAlignment(.center)

            Text("Head to Settings to customize your schedule, then check Today for your first picks.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                onComplete()
            } label: {
                HStack {
                    Image(systemName: "flame.fill")
                    Text("Let's Go!")
                }
            }
            .buttonStyle(GradientButtonStyle())
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
        .buttonStyle(GradientButtonStyle())
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
