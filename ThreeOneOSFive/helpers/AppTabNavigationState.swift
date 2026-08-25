import Foundation

enum AppSection: Int, CaseIterable, Identifiable {
    case home
    case system
    case profile

    var id: Int { rawValue }
}

struct AppTabNavigationState: Equatable {
    private(set) var selectedTab: Int

    init(selectedTab: Int = 0) {
        self.selectedTab = selectedTab
    }

    mutating func select(_ tab: Int) {
        selectedTab = tab
    }
}
