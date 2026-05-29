import Foundation
import SwiftData

/// ViewModel for the Contacts tab — manages imported contacts list
@MainActor
@Observable
final class ContactsViewModel {

    var contacts: [RekindleContact] = []
    var searchText = ""
    var isLoading = false
    var errorMessage: String?

    private var modelContext: ModelContext?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var filteredContacts: [RekindleContact] {
        if searchText.isEmpty {
            return contacts
        }
        return contacts.filter { contact in
            contact.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var activeContacts: [RekindleContact] {
        filteredContacts.filter { $0.isEligible }
    }

    var blockedContacts: [RekindleContact] {
        filteredContacts.filter { $0.isBlocked }
    }

    var snoozedContacts: [RekindleContact] {
        filteredContacts.filter { !$0.isBlocked && $0.isSnoozed }
    }

    var favoriteContacts: [RekindleContact] {
        filteredContacts.filter { $0.isFavorite }
    }

    func loadContacts() {
        guard let modelContext else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let descriptor = FetchDescriptor<RekindleContact>(
                sortBy: [
                    SortDescriptor(\.firstName),
                    SortDescriptor(\.lastName)
                ]
            )
            contacts = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Failed to load contacts: \(error.localizedDescription)"
        }
    }

    func toggleBlock(_ contact: RekindleContact) {
        contact.isBlocked.toggle()
        if contact.isBlocked { contact.isFavorite = false } // blocking drops favorite status
        do {
            try modelContext?.save()
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    /// Set (or clear) a contact's favorite status.
    func setFavorite(_ contact: RekindleContact, to value: Bool) {
        contact.isFavorite = value
        do {
            try modelContext?.save()
        } catch {
            errorMessage = "Failed to update favorite: \(error.localizedDescription)"
        }
    }

    func snooze(_ contact: RekindleContact, until date: Date) {
        contact.snoozedUntil = date
        do {
            try modelContext?.save()
        } catch {
            errorMessage = "Failed to snooze: \(error.localizedDescription)"
        }
    }

    func unsnooze(_ contact: RekindleContact) {
        contact.snoozedUntil = nil
        do {
            try modelContext?.save()
        } catch {
            errorMessage = "Failed to unsnooze: \(error.localizedDescription)"
        }
    }
}
