import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = HomeViewModel()
    @Query private var settingsArray: [AppSettings]
    @State private var favoriteToRemove: RekindleContact?

    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.paddingMedium) {
                    if viewModel.isLoading {
                        loadingView
                    } else {
                        // Standard picks
                        if settings?.isCurrentlyPaused == true {
                            pausedView
                        } else if !viewModel.todayRecommendations.isEmpty {
                            if viewModel.allResolved {
                                allDoneView
                            } else {
                                recommendationsView
                            }
                        } else if viewModel.favoriteRecommendations.isEmpty {
                            // Nothing at all today
                            emptyView
                        }
                        // (standard empty but favorites exist → just show the favorites below)

                        // Favorites sit just below the standard picks and above
                        // "Get More Picks" — so any newly added pick appears above this section.
                        if !viewModel.favoriteRecommendations.isEmpty {
                            favoritesSection
                        }

                        // Get More Picks — only when there are standard picks today and not paused
                        if settings?.isCurrentlyPaused != true && !viewModel.todayRecommendations.isEmpty {
                            morePicksButton
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, Theme.paddingMedium)
                .padding(.top, Theme.paddingSmall)
            }
            .background(Theme.dynamicAppBackground)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.todayRecommendations.isEmpty || !viewModel.favoriteRecommendations.isEmpty {
                        Text("\(viewModel.pendingCount) left")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                viewModel.setup(modelContext: modelContext)
                if let settings {
                    viewModel.loadToday(settings: settings)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.handleReturnFromBackground()
                    // Reload recommendations to pick up widget changes or post-onboarding generation
                    if let settings {
                        viewModel.loadToday(settings: settings)
                    }
                }
            }
            .sheet(item: $viewModel.showSnoozeFor) { contact in
                SnoozeSheet(contactName: contact.fullName) { date in
                    viewModel.snoozeContact(contact, until: date)
                } onBlock: {
                    viewModel.blockContact(contact)
                }
            }
            .overlay {
                if viewModel.showReturnPrompt {
                    returnPromptOverlay
                }
            }
            .alert(
                "Remove from Favorites?",
                isPresented: Binding(
                    get: { favoriteToRemove != nil },
                    set: { if !$0 { favoriteToRemove = nil } }
                ),
                presenting: favoriteToRemove
            ) { contact in
                Button("Remove", role: .destructive) {
                    viewModel.removeFavorite(contact)
                    favoriteToRemove = nil
                }
                Button("Cancel", role: .cancel) { favoriteToRemove = nil }
            } message: { contact in
                Text("\(contact.fullName) will no longer appear in your favorites.")
            }
        }
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.favoriteRecommendations) { rec in
                RecommendationCardView(
                    recommendation: rec,
                    onDone: { viewModel.markDone(rec) },
                    onSkip: {},
                    onPostpone: { viewModel.postpone(rec) },
                    onText: { viewModel.openMessages(for: rec) },
                    onSnooze: {},
                    isFavorite: true,
                    onCall: { viewModel.call(for: rec) },
                    onRemove: { favoriteToRemove = rec.contact }
                )
            }
        }
        // Gold "Keep close" tab tucked onto the top-left of the first favorite card
        .overlay(alignment: .topLeading) {
            Text("KEEP CLOSE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.amber)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.leading, 16)
                .offset(y: -12)
        }
        .padding(.top, 18)
    }

    // MARK: - Return from Messages Prompt

    private var returnPromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(Theme.springAnimation) {
                        viewModel.dismissReturnPrompt()
                    }
                }

            VStack(spacing: 20) {
                Image(systemName: "message.badge.checkmark.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.warmGradient)

                Text("Did you message \(viewModel.pendingMessageRecommendation?.contact?.firstName ?? "them")?")
                    .font(Theme.title)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Button {
                        withAnimation(Theme.springAnimation) {
                            viewModel.dismissReturnPrompt()
                        }
                    } label: {
                        Text("Not yet")
                            .font(Theme.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(Theme.springAnimation) {
                            viewModel.confirmSent()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Yes!")
                        }
                    }
                    .buttonStyle(GradientPillButtonStyle())
                }
            }
            .padding(Theme.paddingLarge)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(Theme.springAnimation, value: viewModel.showReturnPrompt)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Finding your picks...")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var pausedView: some View {
        VStack(spacing: 20) {
            Text("🌙")
                .font(.system(size: 80))
            Text("Recommendations Paused")
                .font(Theme.title)
            Text("Enjoy your break! You can resume in Settings.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.top, 60)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Text("☁️")
                .font(.system(size: 80))
            Text("No Picks Today")
                .font(Theme.title)
            Text("Check back on your next scheduled day, or adjust your schedule in Settings.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.top, 60)
    }

    private var allDoneView: some View {
        VStack(spacing: 20) {
            Text("🎈")
                .font(.system(size: 80))
            Text("You're All Caught Up!")
                .font(Theme.title)
            Text("Great job staying connected today.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.top, 60)
    }

    private var recommendationsView: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.todayRecommendations) { rec in
                RecommendationCardView(
                    recommendation: rec,
                    onDone: { viewModel.markDone(rec) },
                    onSkip: { viewModel.skip(rec) },
                    onPostpone: { viewModel.postpone(rec) },
                    onText: {
                        viewModel.openMessages(for: rec)
                    },
                    onSnooze: {
                        if let contact = rec.contact {
                            viewModel.showSnoozeFor = contact
                        }
                    }
                )
            }
        }
    }

    private var morePicksButton: some View {
        Button {
            if let settings {
                withAnimation(Theme.springAnimation) {
                    viewModel.getMorePicks(
                        count: 1,
                        settings: settings
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flame")
                Text(viewModel.allResolved ? "Want to keep going?" : "Get More Picks")
            }
            .font(Theme.headline)
            .foregroundStyle(Theme.coral)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Theme.coral.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// RekindleContact is already Identifiable via SwiftData's @Model

// MARK: - Snooze Sheet

struct SnoozeSheet: View {
    let contactName: String
    let onSnooze: (Date) -> Void
    var onBlock: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showBlockConfirmation = false

    let options: [(label: String, days: Int)] = [
        ("1 Week", 7),
        ("2 Weeks", 14),
        ("1 Month", 30),
        ("3 Months", 90),
        ("6 Months", 180),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Snooze \(contactName) so they won't be recommended for a while.")
                        .font(Theme.body)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Snooze for...") {
                    ForEach(options, id: \.days) { option in
                        Button {
                            let date = Calendar.current.date(
                                byAdding: .day,
                                value: option.days,
                                to: Date()
                            )!
                            onSnooze(date)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showBlockConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text("Block \(contactName)")
                        }
                    }
                }
            }
            .navigationTitle("Snooze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Block \(contactName)?",
                isPresented: $showBlockConfirmation
            ) {
                Button("Block", role: .destructive) {
                    onBlock?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(contactName) will no longer appear in your recommendations.")
            }
        }
    }
}

// MARK: - Initials Avatar

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 48

    private var backgroundColor: Color {
        let colors: [Color] = [
            Theme.coral,
            Theme.warmOrange,
            Theme.amber,
            Theme.softTeal,
            Color(red: 0.65, green: 0.45, blue: 0.85),
            Color(red: 0.36, green: 0.67, blue: 0.93),
        ]
        let hash = abs(initials.hashValue)
        return colors[hash % colors.count]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.gradient)
                .frame(width: size, height: size)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
