import Foundation

struct FilesTabState: Identifiable {
    var id = UUID()
    var title: String?
    var currentPath: String?
    var navigationPath: [FileBrowserDestination]

    func displayTitle(defaultTitle: String) -> String {
        title ?? defaultTitle
    }
}

struct FilesTabSession {
    var tabs: [FilesTabState] = [FilesTabState(navigationPath: [])]
    var selectedTabID: UUID = UUID()

    init() {
        selectedTabID = tabs[0].id
    }

    var activeTab: FilesTabState? {
        tabs.first { $0.id == selectedTabID }
    }

    mutating func setActiveNavigationPath(_ path: [FileBrowserDestination]) {
        guard let idx = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[idx].navigationPath = path
    }

    mutating func openTab(navigationPath: [FileBrowserDestination] = []) {
        let newTab = FilesTabState(navigationPath: navigationPath)
        tabs.append(newTab)
        selectedTabID = newTab.id
    }

    mutating func selectTab(_ id: UUID) {
        selectedTabID = id
    }

    mutating func closeTab(_ id: UUID) {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if selectedTabID == id {
            selectedTabID = tabs[max(0, idx - 1)].id
        }
    }

    mutating func closeOtherTabs(keeping id: UUID) {
        tabs = tabs.filter { $0.id == id }
        selectedTabID = id
    }

    mutating func renameTab(_ id: UUID, to newTitle: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].title = newTitle.isEmpty ? nil : newTitle
    }
}

struct FileBrowserDestination: Hashable {
    let containerPath: String
    let startPath: String
    let title: String
    let bundleID: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(containerPath)
        hasher.combine(startPath)
        hasher.combine(title)
        hasher.combine(bundleID)
    }

    static func == (lhs: FileBrowserDestination, rhs: FileBrowserDestination) -> Bool {
        lhs.containerPath == rhs.containerPath
            && lhs.startPath == rhs.startPath
            && lhs.title == rhs.title
            && lhs.bundleID == rhs.bundleID
    }
}
