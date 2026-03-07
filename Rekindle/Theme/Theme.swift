import SwiftUI

/// Design system for Rekindle — warm, friendly, adaptive light/dark
struct Theme {

    // MARK: - Accent Colors

    /// Primary warm accent — coral
    static let accent = Color("AccentColor")

    /// Warm coral for light mode, softer for dark
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.42)       // #FF6B6B
    static let warmOrange = Color(red: 1.0, green: 0.54, blue: 0.36)   // #FF8A5C
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.30)        // #FFB84D
    static let softTeal = Color(red: 0.30, green: 0.78, blue: 0.76)    // #4DC7C2

    // MARK: - Gradient

    static let warmGradient = LinearGradient(
        colors: [coral, warmOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGradient = LinearGradient(
        colors: [coral.opacity(0.15), warmOrange.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic Colors

    static let cardBackground = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let tertiaryBackground = Color(.tertiarySystemBackground)

    // MARK: - Status Colors

    static let done = Color.green
    static let skipped = Color.secondary
    static let postponed = amber

    // MARK: - Typography

    static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .semibold)
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)

    // MARK: - Spacing

    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20

    // MARK: - Shadows

    static let cardShadow = Color.black.opacity(0.08)
    static let cardShadowRadius: CGFloat = 12

    // MARK: - Animation

    static let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let easeAnimation = Animation.easeInOut(duration: 0.25)
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: Theme.cardShadowRadius, x: 0, y: 4)
    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.paddingLarge)
            .padding(.vertical, 12)
            .background(Theme.warmGradient)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(Theme.springAnimation, value: configuration.isPressed)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
