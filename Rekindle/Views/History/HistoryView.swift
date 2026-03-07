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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .onAppear {
                viewModel.setup(modelContext: modelContext)
                viewModel.loadHistory()
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(Theme.warmGradient)
            Text("No History Yet")
                .font(Theme.title)
            Text("Your recommendation history will appear here once you start using Rekindle.")
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.paddingLarge)
        }
        .padding()
    }

    private var historyList: some View {
        List {
            ForEach(viewModel.groupedByDate, id: \.date) { group in
                Section {
                    ForEach(group.recommendations) { rec in
                        HistoryItemView(recommendation: rec)
                    }
                } header: {
                    Text(group.date, format: .dateTime.weekday(.wide).month().day())
                }
            }
        }
        .listStyle(.insetGrouped)
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
                .font(.caption2)
            Text(statusText)
                .font(.system(.caption2, design: .rounded, weight: .medium))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var statusIcon: String {
        switch recommendation.status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "forward.fill"
        case .postponed: return "clock.arrow.circlepath"
        case .expired: return "exclamationmark.circle"
        case .pending: return "circle"
        }
    }

    private var statusText: String {
        switch recommendation.status {
        case .done: return "Done"
        case .skipped: return "Skipped"
        case .postponed: return "Later"
        case .expired: return "Missed"
        case .pending: return "Pending"
        }
    }

    private var statusColor: Color {
        switch recommendation.status {
        case .done: return Theme.done
        case .skipped: return .secondary
        case .postponed: return Theme.postponed
        case .expired: return .orange
        case .pending: return .blue
        }
    }
}
