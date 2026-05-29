import WidgetKit
import SwiftUI
import AppIntents
import SwiftData

// MARK: - Data Model

struct WidgetContact: Identifiable {
    let id: String
    let name: String
    let initials: String
    let status: String // raw value of RecommendationStatus
    
    var isDone: Bool { status == "done" }
    var isPending: Bool { status == "pending" }
    var isPostponed: Bool { status == "postponed" }
    var isResolved: Bool { !isPending }
}

struct RekindleEntry: TimelineEntry {
    let date: Date
    let contacts: [WidgetContact]
    let totalCount: Int
    let doneCount: Int
    let isEmpty: Bool
    
    static var placeholder: RekindleEntry {
        RekindleEntry(
            date: Date(),
            contacts: [
                WidgetContact(id: "1", name: "John Smith", initials: "JS", status: "pending"),
                WidgetContact(id: "2", name: "Alice Brown", initials: "AB", status: "pending"),
                WidgetContact(id: "3", name: "Carol Davis", initials: "CD", status: "done"),
            ],
            totalCount: 3,
            doneCount: 1,
            isEmpty: false
        )
    }
    
    static var empty: RekindleEntry {
        RekindleEntry(date: Date(), contacts: [], totalCount: 0, doneCount: 0, isEmpty: true)
    }
}

// MARK: - Timeline Provider

struct RekindleTimelineProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> RekindleEntry {
        .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (RekindleEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(fetchEntry())
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<RekindleEntry>) -> Void) {
        let entry = fetchEntry()
        
        // Schedule next refresh for tomorrow at the notification time
        let nextRefresh = calculateNextRefresh()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
    
    private func fetchEntry() -> RekindleEntry {
        do {
            let container = try SharedModelContainer.create()
            let context = ModelContext(container)
            
            let todayStart = Calendar.current.startOfDay(for: Date())
            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
            
            let descriptor = FetchDescriptor<Recommendation>(
                predicate: #Predicate<Recommendation> { rec in
                    rec.date >= todayStart && rec.date < todayEnd
                },
                sortBy: [SortDescriptor(\.date)]
            )
            
            var recommendations = try context.fetch(descriptor)

            // If no recommendations exist for today, generate them so the widget isn't blank
            // on first load before the app has run. Uses the same weighted selection as the app.
            if recommendations.isEmpty {
                var settingsDescriptor = FetchDescriptor<AppSettings>()
                settingsDescriptor.fetchLimit = 1
                if let settings = try? context.fetch(settingsDescriptor).first {
                    guard !settings.isCurrentlyPaused, settings.isTodayScheduled else {
                        return .empty
                    }

                    let allContacts = try context.fetch(FetchDescriptor<RekindleContact>())
                    let now = Date()
                    let cooldownInterval = TimeInterval(settings.cooldownDays * 86400)

                    let eligible = allContacts.filter { contact in
                        guard !contact.isBlocked else { return false }
                        if let snoozedUntil = contact.snoozedUntil, snoozedUntil > now { return false }
                        if let lastContacted = contact.lastContactedDate,
                           now.timeIntervalSince(lastContacted) < cooldownInterval { return false }
                        return true
                    }

                    guard !eligible.isEmpty else { return .empty }

                    let selected = weightedRandomSample(from: eligible, count: min(settings.contactsPerSession, eligible.count), now: now)
                    for contact in selected {
                        let rec = Recommendation(contact: contact, date: now)
                        contact.lastRecommendedDate = now
                        context.insert(rec)
                        recommendations.append(rec)
                    }
                    try context.save()
                }
            }

            guard !recommendations.isEmpty else {
                return .empty
            }
            
            let contacts = recommendations.map { rec in
                WidgetContact(
                    id: rec.contact?.contactIdentifier ?? UUID().uuidString,
                    name: rec.contact?.fullName ?? "Unknown",
                    initials: rec.contact?.initials ?? "?",
                    status: rec.statusRawValue
                )
            }
            
            let doneCount = recommendations.filter { $0.status == .done }.count
            
            return RekindleEntry(
                date: Date(),
                contacts: contacts,
                totalCount: recommendations.count,
                doneCount: doneCount,
                isEmpty: false
            )
        } catch {
            return .empty
        }
    }
    
    private func calculateNextRefresh() -> Date {
        do {
            let container = try SharedModelContainer.create()
            let context = ModelContext(container)
            
            var descriptor = FetchDescriptor<AppSettings>()
            descriptor.fetchLimit = 1
            
            if let settings = try context.fetch(descriptor).first {
                var components = DateComponents()
                components.hour = settings.notificationHour
                components.minute = settings.notificationMinute
                
                if let nextDate = Calendar.current.nextDate(
                    after: Date(),
                    matching: components,
                    matchingPolicy: .nextTime
                ) {
                    return nextDate
                }
            }
        } catch {}
        
        // Fallback: refresh in 6 hours
        return Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
    }
}

/// Weighted random sample matching the app's RecommendationEngine logic.
/// Contacts not reached out to in longer get higher weight (sqrt of days since last contact).
private func weightedRandomSample(from contacts: [RekindleContact], count: Int, now: Date) -> [RekindleContact] {
    var weights: [(contact: RekindleContact, weight: Double)] = contacts.map { contact in
        let daysSince: Double
        if let lastContacted = contact.lastContactedDate {
            daysSince = max(1, now.timeIntervalSince(lastContacted) / 86400)
        } else if let lastRecommended = contact.lastRecommendedDate {
            daysSince = max(1, now.timeIntervalSince(lastRecommended) / 86400) * 0.8
        } else {
            daysSince = max(1, now.timeIntervalSince(contact.importedDate) / 86400)
        }
        return (contact, sqrt(daysSince))
    }

    var selected: [RekindleContact] = []
    var totalWeight = weights.reduce(0.0) { $0 + $1.weight }

    for _ in 0..<count {
        guard !weights.isEmpty else { break }
        var random = Double.random(in: 0..<totalWeight)
        var pickedIndex = 0
        for (index, item) in weights.enumerated() {
            random -= item.weight
            if random <= 0 { pickedIndex = index; break }
        }
        selected.append(weights[pickedIndex].contact)
        totalWeight -= weights[pickedIndex].weight
        weights.remove(at: pickedIndex)
    }
    return selected
}

// MARK: - Theme Colors (duplicated for widget target isolation)

private enum WidgetTheme {
    static let coral = Color(red: 0.98, green: 0.52, blue: 0.52)
    static let warmOrange = Color(red: 0.98, green: 0.65, blue: 0.45)
    static let sageGreen = Color(red: 0.55, green: 0.76, blue: 0.62)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.40)
    static let softTeal = Color(red: 0.40, green: 0.82, blue: 0.80)
    static let dustyBlue = Color(red: 0.52, green: 0.68, blue: 0.88)
    
    static let warmGradient = LinearGradient(
        colors: [coral, warmOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Always light mode — matches the app
    static let appBackground = Color(red: 0.98, green: 0.97, blue: 0.95) // Creamy off-white #FAF9F6
    static let cardBackground = Color.white
    
    // Rotate through accent colors for avatars
    static func avatarColor(for index: Int) -> Color {
        let colors = [coral, softTeal, dustyBlue, amber, sageGreen, warmOrange]
        return colors[index % colors.count]
    }
}

// MARK: - Widget Views

struct RekindleWidgetView: View {
    let entry: RekindleEntry
    
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget (2×2)

struct SmallWidgetView: View {
    let entry: RekindleEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("Rekindle!")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image("WidgetLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            
            if entry.isEmpty {
                Spacer()
                Text("No picks today.")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Enjoy your day!")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            } else if !entry.contacts.contains(where: { $0.isPending }) {
                Spacer()
                Text("All set!")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Great job staying connected")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                // Contact list
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(entry.contacts.prefix(2).enumerated()), id: \.element.id) { index, contact in
                        HStack(spacing: 8) {
                            // Initial avatar
                            Text(contact.initials)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(
                                    contact.isDone
                                        ? WidgetTheme.sageGreen
                                        : contact.isPostponed
                                            ? WidgetTheme.amber
                                            : WidgetTheme.avatarColor(for: index)
                                )
                                .clipShape(Circle())
                            
                            Text(contact.name)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(contact.isResolved ? .secondary : .primary)
                                .strikethrough(contact.isResolved)
                                .lineLimit(1)
                        }
                    }
                    
                    if entry.contacts.count > 2 {
                        Text("+\(entry.contacts.count - 2) more")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            // Progress pill
            if !entry.isEmpty {
                HStack {
                    Spacer()
                    Text("\(entry.doneCount)/\(entry.totalCount) done")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.doneCount == entry.totalCount ? WidgetTheme.sageGreen : WidgetTheme.coral)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (entry.doneCount == entry.totalCount ? WidgetTheme.sageGreen : WidgetTheme.coral)
                                .opacity(0.15)
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium Widget (4×2)

struct MediumWidgetView: View {
    let entry: RekindleEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack {
                Text("Rekindle!")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !entry.isEmpty {
                    Text("\(entry.doneCount)/\(entry.totalCount) done")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.doneCount == entry.totalCount ? WidgetTheme.sageGreen : WidgetTheme.coral)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (entry.doneCount == entry.totalCount ? WidgetTheme.sageGreen : WidgetTheme.coral)
                                .opacity(0.15)
                        )
                        .clipShape(Capsule())
                }
                
                Image("WidgetLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            
            if entry.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("No picks today. Enjoy your day!")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                Spacer()
            } else if !entry.contacts.contains(where: { $0.isPending }) {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("All set! Great job staying connected.")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                // Contact rows with actions
                VStack(spacing: 4) {
                    ForEach(Array(entry.contacts.prefix(3).enumerated()), id: \.element.id) { index, contact in
                        HStack(spacing: 8) {
                            // Initial avatar
                            Text(contact.initials)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(
                                    contact.isDone
                                        ? WidgetTheme.sageGreen
                                        : contact.isPostponed
                                            ? WidgetTheme.amber
                                            : WidgetTheme.avatarColor(for: index)
                                )
                                .clipShape(Circle())
                            
                            Text(contact.name)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(contact.isResolved ? .secondary : .primary)
                                .strikethrough(contact.isResolved)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if contact.isDone {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text("Done")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(WidgetTheme.sageGreen)
                            } else if contact.isPostponed {
                                HStack(spacing: 2) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 10))
                                    Text("Postponed")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(WidgetTheme.amber)
                            } else if contact.isPending {
                                HStack(spacing: 6) {
                                    Button(intent: MarkDoneIntent(contactID: contact.id)) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                            Text("Done")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(WidgetTheme.sageGreen)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(intent: PostponeIntent(contactID: contact.id)) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(WidgetTheme.amber)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    if entry.contacts.count > 3 {
                        Text("+\(entry.contacts.count - 3) more")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget Definition

struct RekindleWidget: Widget {
    let kind: String = "RekindleWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RekindleTimelineProvider()) { entry in
            RekindleWidgetView(entry: entry)
                .environment(\.colorScheme, .light)
                .containerBackground(for: .widget) {
                    WidgetTheme.appBackground
                }
        }
        .configurationDisplayName("Today's Picks")
        .description("See who Rekindle suggests reaching out to today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    RekindleWidget()
} timeline: {
    RekindleEntry.placeholder
}

#Preview(as: .systemMedium) {
    RekindleWidget()
} timeline: {
    RekindleEntry.placeholder
}
