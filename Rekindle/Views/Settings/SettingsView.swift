import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var viewModel = SettingsViewModel()
    @EnvironmentObject private var contactService: ContactService
    @EnvironmentObject private var notificationService: NotificationService
    @State private var settings: AppSettings?
    @Query(filter: #Predicate<RekindleContact> { $0.isFavorite }) private var favoriteContacts: [RekindleContact]

    private let favoriteCadenceOptions: [(label: String, days: Int)] = [
        ("Daily", 1),
        ("Every 3 Days", 3),
        ("Weekly", 7),
        ("Biweekly", 14),
    ]

    private let cooldownOptions: [(label: String, days: Int)] = [
        ("1 Week", 7),
        ("2 Weeks", 14),
        ("1 Month", 30),
        ("3 Months", 90),
        ("6 Months", 180),
        ("1 Year", 365),
    ]

    private let dayNames = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"),
        (4, "Wednesday"), (5, "Thursday"), (6, "Friday"), (7, "Saturday")
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    settingsForm(settings)
                } else {
                    ProgressView()
                }
            }
            .background(Theme.dynamicAppBackground)
            .navigationTitle("Settings")
            .onAppear {
                viewModel.setup(modelContext: modelContext)
                settings = viewModel.getOrCreateSettings()
            }
        }
    }

    @ViewBuilder
    private func settingsForm(_ settings: AppSettings) -> some View {
        Form {
            // MARK: - Schedule Section
            Section {
                Picker("Frequency", selection: Binding(
                    get: { settings.schedulePreset },
                    set: { newValue in
                        settings.schedulePreset = newValue
                        saveAndReschedule(settings)
                    }
                )) {
                    ForEach(SchedulePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .font(Theme.body)
                
                if settings.schedulePreset == .custom {
                    ForEach(dayNames, id: \.0) { day in
                        Toggle(day.1, isOn: Binding(
                            get: { settings.customDays.contains(day.0) },
                            set: { isOn in
                                var days = settings.customDays
                                if isOn {
                                    days.insert(day.0)
                                } else {
                                    days.remove(day.0)
                                }
                                settings.customDays = days
                                saveAndReschedule(settings)
                            }
                        ))
                        .font(Theme.body)
                    }
                }

                DatePicker(
                    "Notification Time",
                    selection: Binding(
                        get: {
                            var components = DateComponents()
                            components.hour = settings.notificationHour
                            components.minute = settings.notificationMinute
                            return Calendar.current.date(from: components) ?? Date()
                        },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            settings.notificationHour = comps.hour ?? 10
                            settings.notificationMinute = comps.minute ?? 0
                            saveAndReschedule(settings)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .font(Theme.body)
                
            } header: {
                Text("Schedule")
            } footer: {
                Text("When and how often you'd like to receive recommendations.")
            }

            // MARK: - Recommendations Section
            Section {
                Stepper(
                    "Contacts per day: \(settings.contactsPerSession)",
                    value: Binding(
                        get: { settings.contactsPerSession },
                        set: {
                            settings.contactsPerSession = $0
                            viewModel.save()
                        }
                    ),
                    in: 1...20
                )
                .font(Theme.body)

                Picker("Cooldown Period", selection: Binding(
                    get: { settings.cooldownDays },
                    set: {
                        settings.cooldownDays = $0
                        viewModel.save()
                    }
                )) {
                    ForEach(cooldownOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                .font(Theme.body)
                
            } header: {
                Text("Recommendations")
            } footer: {
                Text("After you reach out to someone, they won't be recommended again for the cooldown period.")
            }

            // MARK: - Favorites Section
            Section {
                Toggle("Favorite picks", isOn: Binding(
                    get: { settings.favoritesEnabled },
                    set: {
                        settings.favoritesEnabled = $0
                        viewModel.save()
                    }
                ))
                .font(Theme.body)

                if settings.favoritesEnabled {
                    Stepper(
                        "Favorite picks per day: \(settings.favoritesPerSession)",
                        value: Binding(
                            get: { settings.favoritesPerSession },
                            set: {
                                settings.favoritesPerSession = $0
                                viewModel.save()
                            }
                        ),
                        in: 1...3
                    )
                    .font(Theme.body)

                    Picker("Show a favorite", selection: Binding(
                        get: { settings.favoriteCooldownDays },
                        set: {
                            settings.favoriteCooldownDays = $0
                            viewModel.save()
                        }
                    )) {
                        ForEach(favoriteCadenceOptions, id: \.days) { option in
                            Text(option.label).tag(option.days)
                        }
                    }
                    .font(Theme.body)

                    Button {
                        router.openFavorites()
                    } label: {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Manage Favorites")
                            Spacer()
                            Text("\(favoriteContacts.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .font(Theme.body)
                        .foregroundStyle(Theme.coral)
                    }
                    .accessibilityIdentifier("manageFavorites")
                }
            } header: {
                Text("Favorites")
            } footer: {
                if settings.favoritesEnabled {
                    if favoriteContacts.isEmpty {
                        Text("Star contacts in the Contacts tab to see them here — close friends and family you want to reach out to often, in addition to your regular picks.")
                    } else if settings.favoritesPerSession > favoriteContacts.count {
                        Text("You have \(favoriteContacts.count) favorite\(favoriteContacts.count == 1 ? "" : "s") but ask for \(settings.favoritesPerSession) per day — you'll see all of them every day.")
                    } else {
                        Text("Favorites appear in addition to your regular picks and don't count toward your daily total.")
                    }
                } else {
                    Text("Surface close friends and family on a short, recurring cadence — in addition to your regular recommendations.")
                }
            }

            // MARK: - Pause Section
            Section {
                Toggle("Pause Recommendations", isOn: Binding(
                    get: { settings.isPaused },
                    set: { newValue in
                        settings.isPaused = newValue
                        if !newValue {
                            settings.pausedUntil = nil
                        }
                        saveAndReschedule(settings)
                    }
                ))
                .font(Theme.body)

                if settings.isPaused {
                    Toggle("Auto-resume", isOn: Binding(
                        get: { settings.pausedUntil != nil },
                        set: { hasDate in
                            settings.pausedUntil = hasDate
                                ? Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())
                                : nil
                            viewModel.save()
                        }
                    ))
                    .font(Theme.body)

                    if settings.pausedUntil != nil {
                        DatePicker(
                            "Resume on",
                            selection: Binding(
                                get: { settings.pausedUntil ?? Date() },
                                set: {
                                    settings.pausedUntil = $0
                                    viewModel.save()
                                }
                            ),
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .font(Theme.body)
                    }
                }
            } header: {
                Text("Pause")
            } footer: {
                Text("Temporarily stop all recommendations. Great for vacations or busy periods.")
            }

            // MARK: - Contacts Section
            Section {
                HStack {
                    Text("Permission")
                        .font(Theme.body)
                    Spacer()
                    Text(permissionStatusText)
                        .font(Theme.body)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        try? await contactService.importContacts(modelContext: modelContext)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Refresh Contacts")
                    }
                    .font(Theme.body)
                    .foregroundStyle(Theme.coral)
                }
                .disabled(contactService.authorizationStatus != .authorized || contactService.isImporting)
            } header: {
                Text("Contacts")
            }

            // MARK: - Notifications Section
            Section {
                HStack {
                    Text("Status")
                        .font(Theme.body)
                    Spacer()
                    Text(notificationService.isAuthorized ? "Enabled" : "Disabled")
                        .font(Theme.body)
                        .foregroundStyle(notificationService.isAuthorized ? Theme.sageGreen : Theme.coral)
                }

                if !notificationService.isAuthorized {
                    Button {
                        Task {
                            _ = await notificationService.requestAuthorization()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text("Enable Notifications")
                        }
                        .font(Theme.body)
                        .foregroundStyle(Theme.coral)
                    }
                }
            } header: {
                Text("Notifications")
            }

            // MARK: - About Section
            Section {
                HStack {
                    Text("Version")
                        .font(Theme.body)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(Theme.body)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var permissionStatusText: String {
        switch contactService.authorizationStatus {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Asked"
        case .limited: return "Limited"
        @unknown default: return "Unknown"
        }
    }

    private func saveAndReschedule(_ settings: AppSettings) {
        viewModel.save()
        Task {
            await notificationService.scheduleNotifications(settings: settings)
        }
        // Also reschedule background task for recommendation pre-generation
        BackgroundTaskService.scheduleBackgroundRefresh(settings: settings)
    }
}
