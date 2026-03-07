import Foundation
import Contacts
import SwiftData

/// Service for importing and syncing contacts from iOS Contacts framework
@MainActor
final class ContactService: ObservableObject {

    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published var isImporting = false

    private let contactStore = CNContactStore()

    init() {
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    func updateAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Request access to contacts. Returns true if granted.
    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            await MainActor.run {
                updateAuthorizationStatus()
            }
            return granted
        } catch {
            print("Contact access request failed: \(error)")
            return false
        }
    }

    // MARK: - Import

    /// Import contacts from iOS into SwiftData
    func importContacts(modelContext: ModelContext) async throws {
        guard authorizationStatus == .authorized else { return }

        isImporting = true
        defer { isImporting = false }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .givenName

        // Fetch all system contacts
        var systemContacts: [(id: String, first: String, last: String, phone: String?)] = []

        try contactStore.enumerateContacts(with: request) { contact, _ in
            let phone = contact.phoneNumbers.first?.value.stringValue
            // Only include contacts that have a name
            let hasName = !contact.givenName.isEmpty || !contact.familyName.isEmpty
            if hasName {
                systemContacts.append((
                    id: contact.identifier,
                    first: contact.givenName,
                    last: contact.familyName,
                    phone: phone
                ))
            }
        }

        // Fetch existing RekindleContacts
        let existingDescriptor = FetchDescriptor<RekindleContact>()
        let existingContacts = try modelContext.fetch(existingDescriptor)
        let existingIDs = Set(existingContacts.map(\.contactIdentifier))

        // Add new contacts that don't exist yet
        for sc in systemContacts {
            if !existingIDs.contains(sc.id) {
                let newContact = RekindleContact(
                    contactIdentifier: sc.id,
                    firstName: sc.first,
                    lastName: sc.last,
                    phoneNumber: sc.phone
                )
                modelContext.insert(newContact)
            }
        }

        // Update existing contacts (name or phone may have changed)
        let systemIDMap = Dictionary(uniqueKeysWithValues: systemContacts.map { ($0.id, $0) })
        for existing in existingContacts {
            if let updated = systemIDMap[existing.contactIdentifier] {
                existing.firstName = updated.first
                existing.lastName = updated.last
                existing.phoneNumber = updated.phone
            }
        }

        try modelContext.save()
    }
}
