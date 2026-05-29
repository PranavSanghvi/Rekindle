import SwiftUI

/// Design system for Rekindle — Friendly, soft, pastels, and rounded
struct Theme {

    // MARK: - Accent Colors

    /// Muted, softer coral/salmon
    static let coral = Color(red: 0.98, green: 0.52, blue: 0.52)       // #FA8585
    static let warmOrange = Color(red: 0.98, green: 0.65, blue: 0.45)  // #FA9A72
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.40)        // #FFC766
    /// Deeper gold for readable text/labels on a pale amber tint
    static let goldText = Color(red: 0.70, green: 0.50, blue: 0.12)    // #B38020
    static let softTeal = Color(red: 0.40, green: 0.82, blue: 0.80)    // #66D1CC
    static let sageGreen = Color(red: 0.55, green: 0.76, blue: 0.62)   // #8CBF9E
    static let dustyBlue = Color(red: 0.52, green: 0.68, blue: 0.88)   // #85ADE0

    // MARK: - Gradient

    static let warmGradient = LinearGradient(
        colors: [coral, warmOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGradient = LinearGradient(
        colors: [coral.opacity(0.12), warmOrange.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic Colors (Soft/Friendly)

    /// Off-white in light mode, soft charcoal in dark mode for a less harsh contrast
    static let appBackground = Color("AppBackground") // Make sure to use Color(.systemGroupedBackground) fallback if not in asset catalog, or define dynamically
    static let cardBackground = Color("CardBackground")

    // Dynamic color helpers for backgrounds
    static var dynamicAppBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) // Soft charcoal
                : UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0) // Creamy off-white (#FAF9F6)
        })
    }
    
    static var dynamicCardBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1.0) // Lighter charcoal for cards
                : UIColor.white // Crisp white cards on off-white background
        })
    }

    // MARK: - Status Colors

    static let done = sageGreen
    static let skipped = Color.secondary
    static let postponed = amber

    // MARK: - Typography (Rounded Everywhere)

    static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .bold) // increased weight for softer look
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .rounded, weight: .medium)
    static let caption = Font.system(.caption, design: .rounded, weight: .medium)

    // MARK: - Spacing & Shapes

    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    
    // Hyper-rounded corners for the friendly aesthetic
    static let cornerRadius: CGFloat = 24
    static let cardCornerRadius: CGFloat = 32

    // MARK: - Shadows (Floating/Glowing)

    // A tinted shadow makes cards look like they are glowing rather than casting a harsh black shadow
    static let cardShadow = coral.opacity(0.12)
    static let cardShadowRadius: CGFloat = 16
    static let cardShadowY: CGFloat = 8

    // MARK: - Animation

    // Bouncier spring for a more playful feel
    static let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.65, blendDuration: 0.8)
    static let easeAnimation = Animation.easeInOut(duration: 0.25)
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.dynamicCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: Theme.cardShadowRadius, x: 0, y: Theme.cardShadowY)
    }
}

/// A thick, pill-shaped, "gummy" button style
struct PillButtonStyle: ButtonStyle {
    var primaryColor: Color = Theme.coral
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.paddingLarge)
            .padding(.vertical, 16)
            .frame(maxWidth: 320)
            .background(primaryColor)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Theme.springAnimation, value: configuration.isPressed)
    }
}

/// Variation using the warm gradient
struct GradientPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.paddingLarge)
            .padding(.vertical, 16)
            .frame(maxWidth: 320)
            .background(Theme.warmGradient)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Theme.springAnimation, value: configuration.isPressed)
            // Add a soft glowing shadow to the button itself
            .shadow(color: Theme.coral.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
