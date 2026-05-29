import AppIntents
import SwiftData
import WidgetKit

// MARK: - Mark Done Intent

struct MarkDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as Done"
    static var description: IntentDescription = "Mark a recommended contact as reached out to."
    
    @Parameter(title: "Contact ID")
    var contactID: String
    
    init() {}
    
    init(contactID: String) {
        self.contactID = contactID
    }
    
    func perform() async throws -> some IntentResult {
        let container = try SharedModelContainer.create()
        let context = ModelContext(container)
        
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
        let targetID = contactID
        
        let descriptor = FetchDescriptor<Recommendation>(
            predicate: #Predicate<Recommendation> { rec in
                rec.date >= todayStart && rec.date < todayEnd
            }
        )
        
        let recommendations = try context.fetch(descriptor)
        
        if let match = recommendations.first(where: { $0.contact?.contactIdentifier == targetID }) {
            match.statusRawValue = RecommendationStatus.done.rawValue
            match.actionDate = Date()
            match.contact?.lastContactedDate = Date()
            try context.save()
        }
        
        // Refresh the widget
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}

// MARK: - Postpone Intent

struct PostponeIntent: AppIntent {
    static var title: LocalizedStringResource = "Postpone"
    static var description: IntentDescription = "Postpone reaching out to this contact."
    
    @Parameter(title: "Contact ID")
    var contactID: String
    
    init() {}
    
    init(contactID: String) {
        self.contactID = contactID
    }
    
    func perform() async throws -> some IntentResult {
        let container = try SharedModelContainer.create()
        let context = ModelContext(container)
        
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
        let targetID = contactID
        
        let descriptor = FetchDescriptor<Recommendation>(
            predicate: #Predicate<Recommendation> { rec in
                rec.date >= todayStart && rec.date < todayEnd
            }
        )
        
        let recommendations = try context.fetch(descriptor)
        
        if let match = recommendations.first(where: { $0.contact?.contactIdentifier == targetID }) {
            match.statusRawValue = RecommendationStatus.postponed.rawValue
            match.actionDate = Date()
            try context.save()
        }
        
        // Refresh the widget
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}
