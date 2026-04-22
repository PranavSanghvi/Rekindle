import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading history...")
                } else if viewModel.recommendations.isEmpty {
                    emptyView
                } else {
                    historyList
                }
            }
            .background(Theme.dynamicAppBackground)
            .navigationTitle("History")
            .onAppear {
                viewModel.setup(modelContext: modelContext)
                viewModel.loadHistory()
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Text("🕰️")
                .font(.system(size: 80))
            Text("No History Yet")
                .font(Theme.title)
            Text("Your recommendation history will appear here once you start using Rekindle.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.paddingLarge)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.paddingLarge) {
                ForEach(viewModel.groupedByDate, id: \.date) { group in
                    historySection(date: group.date, recommendations: group.recommendations)
                }
            }
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.vertical, Theme.paddingLarge)
        }
    }

    @ViewBuilder
    private func historySection(date: Date, recommendations: [Recommendation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.paddingMedium)
            
            VStack(spacing: 0) {
                ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, rec in
                    HistoryItemView(recommendation: rec)
                        .padding(.vertical, 12)
                        .padding(.horizontal, Theme.paddingMedium)
                    
                    if index != recommendations.count - 1 {
                        Divider()
                            .padding(.leading, 64)
                    }
                }
            }
            .cardStyle() // Soft UI rounded corners and floating shadow
        }
    }
}

// MARK: - History Item

struct HistoryItemView: View {
    let recommendation: Recommendation

    private var contact: RekindleContact? { recommendation.contact }

    var body: some View {
        HStack(spacing: 12) {
            if let contact {
                InitialsAvatar(initials: contact.initials, size: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact?.fullName ?? "Unknown")
                    .font(Theme.body)

                if let actionDate = recommendation.actionDate {
                    Text(actionDate, format: .dateTime.hour().minute())
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2.weight(.bold))
            Text(statusText)
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var statusIcon: String {
        switch recommendation.status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "forward.fill"
        case .postponed: return "clock.arrow.circlepath"
        case .expired: return "exclamationmark.triangle.fill"
        case .snoozed: return "moon.zzz.fill"
        case .blocked: return "hand.raised.fill"
        case .pending: return "circle"
        }
    }

    private var statusText: String {
        switch recommendation.status {
        case .done: return "Done"
        case .skipped: return "Skipped"
        case .postponed: return "Later"
        case .expired: return "Missed"
        case .snoozed: return "Snoozed"
        case .blocked: return "Blocked"
        case .pending: return "Pending"
        }
    }

    private var statusColor: Color {
        switch recommendation.status {
        case .done: return Theme.done
        case .skipped: return .secondary
        case .postponed: return Theme.postponed
        case .expired: return Theme.amber
        case .snoozed: return Theme.amber
        case .blocked: return .red
        case .pending: return Theme.dustyBlue
        }
    }
}
