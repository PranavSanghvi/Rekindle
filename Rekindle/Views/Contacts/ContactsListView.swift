import SwiftUI
import SwiftData

struct ContactsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ContactsViewModel()
    @EnvironmentObject private var contactService: ContactService
    @State private var showSnoozeSheet = false
    @State private var contactToSnooze: RekindleContact?
    @State private var selectedFilter: ContactFilter = .active

    enum ContactFilter: String, CaseIterable {
        case active = "Active"
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
            }
            .sheet(item: $contactToSnooze) { contact in
                SnoozeSheet(contactName: contact.fullName) { date in
                    viewModel.snooze(contact, until: date)
                } onBlock: {
                    viewModel.toggleBlock(contact)
                }
            }
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
        case .snoozed: return viewModel.snoozedContacts
        case .blocked: return viewModel.blockedContacts
        }
    }

    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Text(selectedFilter == .snoozed ? "No snoozed contacts" : "No blocked contacts")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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

            // Ellipsis Menu replaces swipe actions
            Menu {
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
