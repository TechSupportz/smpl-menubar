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
        case .hidden: "Shows when you hover the bar"
        case .alwaysHidden: "Shows when you click the dot"
        }
    }
    var symbol: String {
        switch self {
        case .visible: "eye"
        case .hidden: "cursorarrow.rays"
        case .alwaysHidden: "eye.slash"
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
    /// Apps switched off in System Settings, not by this app. Left alone until dragged into a section.
    private(set) var switchedOffElsewhere: [MenuApp] = []
    private(set) var accessError = false

    /// Hidden section revealed by hovering the menu bar.
    private(set) var hoverShown = false
    /// Everything revealed by clicking the dot.
    private(set) var clickShown = false
    var isShowing: Bool { hoverShown || clickShown }

    /// Sets both flags together and writes the switches at most once, and only when
    /// what's on screen changes: every write makes macOS rebuild the affected items.
    func setShown(hover: Bool, click: Bool) {
        let wasShowing = isShowing, wasClick = clickShown
        hoverShown = hover
        clickShown = click
        if isShowing != wasShowing || clickShown != wasClick { apply() }
    }

    private var sections: [String: Section] {
        didSet { Defaults.sections = sections.mapValues(\.rawValue) }
    }
    /// Apps this app switched off, and only those. Moving one back to Visible, or quitting,
    /// switches it on again; apps you switched off yourself in System Settings are never touched.
    private var managed: Set<String> {
        didSet { Defaults.managed = managed }
    }

    private let ownID = Bundle.main.bundleIdentifier ?? ""
    static let dividerName = "Divider"
    /// App bundle ID → bundle IDs that own its menu bar items.
    private var itemOwners: [String: Set<String>] = [:]
    /// The switches from the last confirmed write.
    private var lastWritten: [String: Bool]?

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
        // Dragging an app that was switched off elsewhere hands it to this app.
        let adopting = switchedOffElsewhere.contains { $0.id == id }
        if adopting { managed.insert(id) }
        guard adopting || sections[id] != section else { return }
        sections[id] = section
        apply()
        refresh()
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
        var listed: [MenuApp] = []
        var elsewhere: [MenuApp] = []
        for entry in entries where entry.bundleID != ownID && seen.insert(entry.bundleID).inserted {
            let section = sections[entry.bundleID] ?? .visible
            if section == .visible, !entry.isAllowed, !managed.contains(entry.bundleID) {
                elsewhere.append(Self.makeApp(entry.bundleID))
                continue
            }
            let isRunning = running.contains(entry.bundleID) || entry.itemBundleIDs.contains(where: running.contains)
            guard isRunning || section != .visible else { continue }
            listed.append(Self.makeApp(entry.bundleID))
        }
        let byName: (MenuApp, MenuApp) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        apps = listed.sorted(by: byName)
        switchedOffElsewhere = elsewhere.sorted(by: byName)
    }

    /// Writes the switches the current state calls for.
    func apply() {
        var changes: [String: Bool] = [:]
        for id in managed where (sections[id] ?? .visible) == .visible {
            changes[id] = true
        }
        for (id, section) in sections where id != ownID {
            switch section {
            case .visible: break
            case .hidden: changes[id] = hoverShown || clickShown
            case .alwaysHidden: changes[id] = clickShown
            }
        }
        write(changes)
    }

    /// On quit, switches back on every app this app switched off. `managed` is kept, so the
    /// next launch hides them again, and a crash before this leaves enough to recover.
    func restoreForQuit() {
        let changes = Dictionary(uniqueKeysWithValues: managed.map { ($0, true) })
        accessError = !ControlCenterList.setAllowed(changes)
    }

    private func write(_ changes: [String: Bool]) {
        // Same switches as last time (e.g. hover ending while everything is shown): nothing to do.
        guard changes != lastWritten || accessError else { return }
        // Order only matters when items reappear: Hidden, then Always Hidden, left of the dot.
        // macOS only reads the order when an item appears, so a pure hide skips it.
        if changes.values.contains(true) {
            func owners(_ section: Section) -> Set<String> {
                sections.filter { $0.value == section }.keys.reduce(into: Set<String>()) {
                    $0.formUnion(itemOwners[$1] ?? [$1])
                }
            }
            MenuBarLayout.place(ownID: ownID, dividerName: Self.dividerName, hiddenOwners: owners(.hidden), alwaysHiddenOwners: owners(.alwaysHidden))
        }
        let ok = ControlCenterList.setAllowed(changes)
        accessError = !ok
        // Only after a confirmed write: switched off → ours; restored in Visible → no longer ours.
        guard ok else { return }
        lastWritten = changes
        var updated = managed
        for (id, allowed) in changes {
            if !allowed {
                updated.insert(id)
            } else if (sections[id] ?? .visible) == .visible {
                updated.remove(id)
            }
        }
        if updated != managed { managed = updated }
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
