import SwiftUI
import SwiftData

struct ContactsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ContactsViewModel()
    @EnvironmentObject private var contactService: ContactService
    @State private var showSnoozeSheet = false
    @State private var contactToSnooze: RekindleContact?
    @State private var contactToUnfavorite: RekindleContact?
    @State private var selectedFilter: ContactFilter = .active

    enum ContactFilter: String, CaseIterable {
        case active = "Active"
        case favorites = "Favorites"
        case snoozed = "Snoozed"
        case blocked = "Blocked"
    }

    var body: some View {
        NavigationStack {
            Group {
                if contactService.authorizationStatus != .authorized {
                    permissionView
                } else if viewModel.isLoading {
                    ProgressView("Loading contacts...")
                } else if viewModel.contacts.isEmpty {
                    noContactsView
                } else {
                    contactsList
                }
            }
            .background(Theme.dynamicAppBackground)
            .navigationTitle("Contacts")
            .searchable(text: $viewModel.searchText, prompt: "Search contacts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if contactService.authorizationStatus == .authorized {
                        Button {
                            Task {
                                try? await contactService.importContacts(modelContext: modelContext)
                                viewModel.loadContacts()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .disabled(contactService.isImporting)
                    }
                }
            }
            .onAppear {
                viewModel.setup(modelContext: modelContext)
                viewModel.loadContacts()
                if router.focusFavorites {
                    selectedFilter = .favorites
                    router.focusFavorites = false
                }
            }
            .onChange(of: router.focusFavorites) { _, focus in
                if focus {
                    selectedFilter = .favorites
                    router.focusFavorites = false
                }
            }
            .sheet(item: $contactToSnooze) { contact in
                SnoozeSheet(contactName: contact.fullName) { date in
                    viewModel.snooze(contact, until: date)
                } onBlock: {
                    viewModel.toggleBlock(contact)
                }
            }
            .alert(
                "Remove from Favorites?",
                isPresented: Binding(
                    get: { contactToUnfavorite != nil },
                    set: { if !$0 { contactToUnfavorite = nil } }
                ),
                presenting: contactToUnfavorite
            ) { contact in
                Button("Remove", role: .destructive) {
                    viewModel.setFavorite(contact, to: false)
                    contactToUnfavorite = nil
                }
                Button("Cancel", role: .cancel) { contactToUnfavorite = nil }
            } message: { contact in
                Text("\(contact.fullName) will no longer appear in your favorites.")
            }
        }
    }

    /// Star tapped: add immediately, but confirm before removing.
    private func toggleFavorite(_ contact: RekindleContact) {
        if contact.isFavorite {
            contactToUnfavorite = contact
        } else {
            viewModel.setFavorite(contact, to: true)
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(Theme.warmGradient)

            Text("Contacts Access Needed")
                .font(Theme.title)

            Text("Rekindle needs access to your contacts to suggest people to reconnect with. We never modify or share your contacts.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.paddingLarge)

            Button {
                Task {
                    let granted = await contactService.requestAccess()
                    if granted {
                        try? await contactService.importContacts(modelContext: modelContext)
                        viewModel.loadContacts()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text("Allow Access")
                }
            }
            .buttonStyle(GradientPillButtonStyle())

            if contactService.authorizationStatus == .denied {
                Text("You can enable access in Settings → Privacy → Contacts")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noContactsView: some View {
        VStack(spacing: 20) {
            Text("📇")
                .font(.system(size: 80))
            Text("No Contacts Found")
                .font(Theme.title)
            Text("Tap the refresh button to import your contacts.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Contacts List (Custom Setup)

    private var contactsList: some View {
        ScrollView {
            // Filter tabs
            Picker("Filter", selection: $selectedFilter) {
                ForEach(ContactFilter.allCases, id: \.self) { filter in
                    Text(filterLabel(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.top, Theme.paddingMedium)

            LazyVStack(spacing: Theme.paddingLarge) {
                let contacts = filteredContacts
                if contacts.isEmpty {
                    emptyFilterView
                } else {
                    contactSectionBody(contacts: contacts)
                }
            }
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.vertical, Theme.paddingLarge)
        }
    }

    private func filterLabel(_ filter: ContactFilter) -> String {
        switch filter {
        case .active: return "Active"
        case .favorites:
            let count = viewModel.favoriteContacts.count
            return count > 0 ? "⭐ \(count)" : "⭐"
        case .snoozed:
            let count = viewModel.snoozedContacts.count
            return count > 0 ? "Snoozed (\(count))" : "Snoozed"
        case .blocked:
            let count = viewModel.blockedContacts.count
            return count > 0 ? "Blocked (\(count))" : "Blocked"
        }
    }

    private var filteredContacts: [RekindleContact] {
        switch selectedFilter {
        case .active: return viewModel.activeContacts
        case .favorites: return viewModel.favoriteContacts
        case .snoozed: return viewModel.snoozedContacts
        case .blocked: return viewModel.blockedContacts
        }
    }

    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Text(emptyFilterMessage)
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, Theme.paddingLarge)
    }

    private var emptyFilterMessage: String {
        switch selectedFilter {
        case .favorites: return "No favorites yet.\nTap the star on a contact to add them."
        case .snoozed: return "No snoozed contacts"
        case .blocked: return "No blocked contacts"
        case .active: return "No contacts"
        }
    }

    @ViewBuilder
    private func contactSectionBody(contacts: [RekindleContact]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                contactRow(contact)
                if index != contacts.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                }
            }
        }
        .cardStyle()
    }

    private func contactRow(_ contact: RekindleContact) -> some View {
        HStack(spacing: 12) {
            InitialsAvatar(initials: contact.initials, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.fullName)
                    .font(Theme.body)

                if contact.isBlocked {
                    Text("Blocked")
                        .font(Theme.caption)
                        .foregroundStyle(.red)
                } else if contact.isSnoozed, let until = contact.snoozedUntil {
                    Text("Snoozed until \(until, format: .dateTime.month().day())")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.amber)
                }
            }

            Spacer()

            // Favorite star toggle (hidden for blocked contacts)
            if !contact.isBlocked {
                Button {
                    toggleFavorite(contact)
                } label: {
                    Image(systemName: contact.isFavorite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(contact.isFavorite ? Theme.amber : Color.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }

            // Ellipsis Menu replaces swipe actions
            Menu {
                if !contact.isBlocked {
                    Button(contact.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            toggleFavorite(contact)
                        }
                    }
                }

                if contact.isBlocked {
                    Button("Unblock", role: .none) {
                        // Workaround: delay slightly to let menu dismiss
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewModel.toggleBlock(contact)
                        }
                    }
                } else {
                    Button("Block", role: .destructive) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewModel.toggleBlock(contact)
                        }
                    }
                }
                
                if !contact.isBlocked {
                    if contact.isSnoozed {
                        Button("Unsnooze", role: .none) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewModel.unsnooze(contact)
                            }
                        }
                    } else {
                        Button("Snooze...", role: .none) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                contactToSnooze = contact
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.paddingMedium)
        // Also allow long press on the row itself to bring up the same context menu
        .contextMenu {
            if !contact.isBlocked {
                Button(contact.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                    toggleFavorite(contact)
                }
            }
            if contact.isBlocked {
                Button("Unblock") { viewModel.toggleBlock(contact) }
            } else {
                Button("Block", role: .destructive) { viewModel.toggleBlock(contact) }
            }
            if !contact.isBlocked {
                if contact.isSnoozed {
                    Button("Unsnooze") { viewModel.unsnooze(contact) }
                } else {
                    Button("Snooze...") { contactToSnooze = contact }
                }
            }
        }
    }
}
