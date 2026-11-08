import AppKit
import Observation

enum Section: String, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
    var subtitle: String {
        switch self {
        case .visible: "Always in the menu bar"
        case .hidden: "Shown on hover, gone 2s after"
        case .alwaysHidden: "Shown when you click the dot"
        }
    }
}

struct MenuApp: Identifiable, Hashable {
    let id: String // bundle ID
    let name: String
    let icon: NSImage
}

@MainActor
@Observable
final class Model {
    private(set) var apps: [MenuApp] = []
    private(set) var accessError = false

    /// Hidden section revealed by hovering the dot.
    var hoverShown = false { didSet { if hoverShown != oldValue { apply() } } }
    /// Everything revealed by clicking the dot.
    var clickShown = false { didSet { if clickShown != oldValue { apply() } } }
    var isShowing: Bool { hoverShown || clickShown }

    private var sections: [String: Section] {
        didSet { Defaults.sections = sections.mapValues(\.rawValue) }
    }
    /// Apps this app has switched off, so moving one back to Visible switches it on again
    /// without touching apps you switched off yourself in System Settings.
    private var managed: Set<String> {
        didSet { Defaults.managed = managed }
    }

    private let ownID = Bundle.main.bundleIdentifier ?? ""
    static let dividerName = "Divider"
    /// App bundle ID → bundle IDs that own its menu bar items.
    private var itemOwners: [String: Set<String>] = [:]

    init() {
        sections = Defaults.sections.compactMapValues(Section.init(rawValue:))
        managed = Defaults.managed
        refresh()
    }

    func section(of app: MenuApp) -> Section { sections[app.id] ?? .visible }

    func apps(in section: Section) -> [MenuApp] {
        apps.filter { self.section(of: $0) == section }
    }

    func move(_ id: String, to section: Section) {
        guard sections[id] != section else { return }
        sections[id] = section
        apply()
    }

    /// Re-reads the list and shows the apps that currently have menu bar items.
    func refresh() {
        guard let entries = ControlCenterList.read() else {
            accessError = true
            return
        }
        accessError = false
        itemOwners = Dictionary(entries.map { ($0.bundleID, Set($0.itemBundleIDs + [$0.bundleID])) },
                                uniquingKeysWith: { $0.union($1) })
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        ControlCenterList.backupOnce(to: support.appending(path: "smpl-menubar/controlcenter-backup.plist"))
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var seen = Set<String>()
        apps = entries.compactMap { entry -> MenuApp? in
            guard entry.bundleID != ownID, seen.insert(entry.bundleID).inserted else { return nil }
            // First time we see an app you'd already switched off, keep it off: Always Hidden.
            if sections[entry.bundleID] == nil, !entry.isAllowed {
                sections[entry.bundleID] = .alwaysHidden
                managed.insert(entry.bundleID)
            }
            let isRunning = running.contains(entry.bundleID) || entry.itemBundleIDs.contains(where: running.contains)
            guard isRunning || sections[entry.bundleID, default: .visible] != .visible else { return nil }
            return Self.makeApp(entry.bundleID)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Writes the switches the current state calls for.
    func apply() {
        var changes: [String: Bool] = [:]
        for (id, section) in sections where id != ownID {
            switch section {
            case .visible:
                if managed.contains(id) {
                    changes[id] = true
                    managed.remove(id)
                }
            case .hidden:
                changes[id] = hoverShown || clickShown
                managed.insert(id)
            case .alwaysHidden:
                changes[id] = clickShown
                managed.insert(id)
            }
        }
        // Order first, so items that reappear land left of the dot: Hidden, then Always Hidden.
        func owners(_ section: Section) -> Set<String> {
            sections.filter { $0.value == section }.keys.reduce(into: Set<String>()) {
                $0.formUnion(itemOwners[$1] ?? [$1])
            }
        }
        MenuBarLayout.place(ownID: ownID, dividerName: Self.dividerName, hiddenOwners: owners(.hidden), alwaysHiddenOwners: owners(.alwaysHidden))
        accessError = !ControlCenterList.setAllowed(changes)
    }

    private static func makeApp(_ id: String) -> MenuApp {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
        return MenuApp(id: id, name: name, icon: icon)
    }
}

private enum Defaults {
    static var sections: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "sections") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "sections") }
    }
    static var managed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "managed") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "managed") }
    }
}
