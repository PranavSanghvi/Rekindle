import SwiftUI
import ContactsUI

/// Button that presents the iOS 18 limited-access picker so the user can change
/// which contacts Rekindle can see, without leaving the app.
/// Only exists on iOS 18+ — callers gate with `if #available(iOS 18.0, *)`.
@available(iOS 18.0, *)
struct ManageContactSelectionButton<Label: View>: View {
    let onSelectionChanged: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            label()
        }
        .contactAccessPicker(isPresented: $showPicker) { _ in
            onSelectionChanged()
        }
    }
}

/// Banner shown above the contacts list when the user granted limited access.
struct LimitedAccessBanner: View {
    let onSelectionChanged: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title3)
                .foregroundStyle(Theme.dustyBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited access")
                    .font(Theme.headline)
                    .foregroundStyle(.primary)
                Text("Rekindle only sees the contacts you've shared.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if #available(iOS 18.0, *) {
                ManageContactSelectionButton(onSelectionChanged: onSelectionChanged) {
                    Text("Manage")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.coral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.paddingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.dustyBlue.opacity(0.12))
        )
    }
}
