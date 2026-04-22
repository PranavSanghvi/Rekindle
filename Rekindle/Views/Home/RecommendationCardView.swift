import SwiftUI

struct RecommendationCardView: View {
    let recommendation: Recommendation
    let onDone: () -> Void
    let onSkip: () -> Void
    let onPostpone: () -> Void
    let onText: () -> Void
    let onSnooze: () -> Void

    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSwipeHint = false

    private var contact: RekindleContact? { recommendation.contact }
    private var isResolved: Bool { recommendation.status != .pending }

    // Swipe threshold to trigger "mark as sent"
    private let swipeThreshold: CGFloat = 120

    var body: some View {
        ZStack(alignment: .leading) {
            // Green background revealed on swipe
            if dragOffset > 0 || showSwipeHint {
                swipeBackground
            }

            // Card content
            VStack(spacing: 0) {
                headerView
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isResolved {
                            withAnimation(Theme.springAnimation) {
                                isExpanded.toggle()
                            }
                        }
                    }

                if isExpanded && !isResolved {
                    Divider()
                        .padding(.horizontal, Theme.paddingMedium)
                    expandedActions
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
            .cardStyle()
            .offset(x: dragOffset)
            .gesture(
                isResolved ? nil : swipeGesture
            )
        }
        .opacity(isResolved ? 0.6 : 1.0)
        .animation(Theme.easeAnimation, value: isResolved)
    }

    // MARK: - Swipe background

    private var swipeBackground: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
            Text("Sent!")
                .font(Theme.headline)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.leading, Theme.paddingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.sageGreen.gradient)
        )
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Only allow right swipe
                if value.translation.width > 0 {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                if value.translation.width > swipeThreshold {
                    performDoneAnimation()
                } else {
                    withAnimation(Theme.springAnimation) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// Brief swipe-right-and-back animation, then mark as done
    private func performDoneAnimation() {
        // Show the green background briefly
        showSwipeHint = true

        // Animate card to the right
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = UIScreen.main.bounds.width * 0.4
        }

        // Snap back and mark as done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(Theme.springAnimation) {
                dragOffset = 0
                showSwipeHint = false
                isExpanded = false
            }
            onDone()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            if let contact {
                InitialsAvatar(initials: contact.initials, size: 48)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(contact?.fullName ?? "Unknown")
                    .font(Theme.headline)
                    .foregroundStyle(isResolved ? .secondary : .primary)

                if isResolved {
                    statusBadge
                }
            }

            Spacer()

            if !isResolved {
                // Quick message button — opens Messages directly
                Button(action: onText) {
                    Image(systemName: "message.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.coral)
                }
                .buttonStyle(.plain)

                // Expand indicator
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .padding(Theme.paddingMedium)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2.weight(.bold))
            Text(statusText)
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(statusColor)
    }

    // MARK: - Expanded Actions

    private var expandedActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActionButton(
                    title: "Done",
                    icon: "checkmark.circle.fill",
                    color: Theme.done,
                    action: {
                        performDoneAnimation()
                    }
                )

                ActionButton(
                    title: "Skip",
                    icon: "forward.fill",
                    color: .secondary,
                    action: {
                        withAnimation(Theme.springAnimation) {
                            onSkip()
                            isExpanded = false
                        }
                    }
                )

                ActionButton(
                    title: "Postpone",
                    icon: "clock.arrow.circlepath",
                    color: Theme.postponed,
                    action: {
                        withAnimation(Theme.springAnimation) {
                            onPostpone()
                            isExpanded = false
                        }
                    }
                )
            }

            Button(action: onSnooze) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                        .font(.caption)
                    Text("Snooze this person")
                        .font(Theme.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.vertical, 14)
    }

    // MARK: - Status helpers

    private var statusIcon: String {
        switch recommendation.status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "forward.fill"
        case .postponed: return "clock.arrow.circlepath"
        case .expired: return "exclamationmark.circle"
        case .snoozed: return "moon.zzz.fill"
        case .blocked: return "hand.raised.fill"
        case .pending: return "circle"
        }
    }

    private var statusText: String {
        switch recommendation.status {
        case .done: return "Reached out"
        case .skipped: return "Skipped"
        case .postponed: return "Postponed"
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
        case .expired: return .orange
        case .snoozed: return Theme.amber
        case .blocked: return .red
        case .pending: return .primary
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
