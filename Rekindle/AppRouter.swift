import SwiftUI

/// Lightweight app-wide navigation state for cross-tab deep links
/// (e.g. Settings → "Manage Favorites" jumps to the Contacts tab's Favorites filter).
@MainActor
@Observable
final class AppRouter {
    /// Selected tab index (0 = Today, 1 = Contacts, 2 = History, 3 = Settings)
    var selectedTab: Int = 0

    /// When set, the Contacts tab switches to its Favorites filter and resets this flag.
    var focusFavorites: Bool = false

    /// Jump to the Contacts tab, focused on Favorites.
    func openFavorites() {
        focusFavorites = true
        selectedTab = 1
    }
}
