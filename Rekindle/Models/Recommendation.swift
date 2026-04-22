import Foundation
import SwiftData

/// Status of a recommendation action
enum RecommendationStatus: String, Codable {
    case pending    // Not yet acted on
    case done       // User reached out
    case skipped    // User chose to skip
    case postponed  // Put back in pool for next time
    case expired    // Never acted on from a previous day
    case snoozed    // Contact was snoozed
    case blocked    // Contact was blocked
}

@Model
final class Recommendation {
    /// When this recommendation was generated
    var date: Date = Date()

    /// What the user did with this recommendation
    var statusRawValue: String = RecommendationStatus.pending.rawValue

    /// When the user acted on this recommendation
    var actionDate: Date?

    /// The contact being recommended
    var contact: RekindleContact?

    var status: RecommendationStatus {
        get { RecommendationStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(contact: RekindleContact, date: Date = Date()) {
        self.contact = contact
        self.date = date
        self.statusRawValue = RecommendationStatus.pending.rawValue
    }
}
