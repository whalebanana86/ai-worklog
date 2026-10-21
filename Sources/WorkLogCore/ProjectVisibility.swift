import Foundation

/// Sidebar-only preferences. Hiding a row never changes the underlying work records.
public struct ProjectVisibility {
    private static let defaultsKey = "hiddenSidebarProjectPaths"
    private let defaults: UserDefaults
    private let persists: Bool
    public private(set) var hiddenPaths: Set<String>

    public init(defaults: UserDefaults = .standard, persists: Bool = true) {
        self.defaults = defaults
        self.persists = persists
        hiddenPaths = persists ? Set(defaults.stringArray(forKey: Self.defaultsKey) ?? []) : []
    }

    public func isHidden(_ path: String) -> Bool { hiddenPaths.contains(path) }

    public mutating func setHidden(_ hidden: Bool, for path: String) {
        if hidden { hiddenPaths.insert(path) }
        else { hiddenPaths.remove(path) }
        save()
    }

    public mutating func showAll() {
        hiddenPaths.removeAll()
        save()
    }

    private func save() {
        guard persists else { return }
        defaults.set(hiddenPaths.sorted(), forKey: Self.defaultsKey)
    }
}
