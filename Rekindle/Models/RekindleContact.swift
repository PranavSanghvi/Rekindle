import Foundation
import SwiftData

@Model
final class RekindleContact {
    /// The CNContact identifier for linking back to iOS Contacts
    @Attribute(.unique) var contactIdentifier: String

    var firstName: String
    var lastName: String
    var phoneNumber: String?

    /// Whether this contact is excluded from recommendations
    var isBlocked: Bool = false

    /// Whether this contact is a favorite — surfaced on a short, recurring cadence
    /// in addition to (and separate from) the standard recommendations.
    var isFavorite: Bool = false

    /// If set, contact is temporarily excluded until this date
    var snoozedUntil: Date?

    /// When this contact was last recommended
    var lastRecommendedDate: Date?

    /// When the user last marked "Done / I reached out"
    var lastContactedDate: Date?

    /// When this contact was first imported into the app
    var importedDate: Date = Date()

    /// All recommendations involving this contact
    @Relationship(deleteRule: .cascade, inverse: \Recommendation.contact)
    var recommendations: [Recommendation] = []

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var initials: String {
        let first = firstName.first.map(String.init) ?? ""
        let last = lastName.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    /// Whether this contact is currently snoozed
    var isSnoozed: Bool {
        guard let snoozedUntil else { return false }
        return snoozedUntil > Date()
    }

    /// Whether this contact is eligible for recommendation
    var isEligible: Bool {
        !isBlocked && !isSnoozed
    }

    init(
        contactIdentifier: String,
        firstName: String,
        lastName: String,
        phoneNumber: String? = nil
    ) {
        self.contactIdentifier = contactIdentifier
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
    }
}
