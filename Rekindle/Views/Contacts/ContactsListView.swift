import SwiftUI
import SwiftData

struct ContactsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ContactsViewModel()
    @EnvironmentObject private var contactService: ContactService
    @State private var showSnoozeSheet = false
    @State private var contactToSnooze: RekindleContact?

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
            .background(Color(.systemGroupedBackground))
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
            .buttonStyle(GradientButtonStyle())

            if contactService.authorizationStatus == .denied {
                Text("You can enable access in Settings → Privacy → Contacts")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var noContactsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Contacts Found")
                .font(Theme.title)
            Text("Tap the refresh button to import your contacts.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Contacts List

    private var contactsList: some View {
        List {
            if !viewModel.activeContacts.isEmpty {
                Section {
                    ForEach(viewModel.activeContacts) { contact in
                        contactRow(contact)
                    }
                } header: {
                    Text("Active (\(viewModel.activeContacts.count))")
                }
            }

            if !viewModel.snoozedContacts.isEmpty {
                Section {
                    ForEach(viewModel.snoozedContacts) { contact in
                        contactRow(contact)
                    }
                } header: {
                    Text("Snoozed (\(viewModel.snoozedContacts.count))")
                }
            }

            if !viewModel.blockedContacts.isEmpty {
                Section {
                    ForEach(viewModel.blockedContacts) { contact in
                        contactRow(contact)
                    }
                } header: {
                    Text("Blocked (\(viewModel.blockedContacts.count))")
                }
            }
        }
        .listStyle(.insetGrouped)
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
        }
        .swipeActions(edge: .trailing) {
            if contact.isBlocked {
                Button("Unblock") {
                    viewModel.toggleBlock(contact)
                }
                .tint(.green)
            } else {
                Button("Block") {
                    viewModel.toggleBlock(contact)
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading) {
            if !contact.isBlocked {
                if contact.isSnoozed {
                    Button("Unsnooze") {
                        viewModel.unsnooze(contact)
                    }
                    .tint(Theme.softTeal)
                } else {
                    Button("Snooze") {
                        contactToSnooze = contact
                    }
                    .tint(Theme.amber)
                }
            }
        }
    }
}
