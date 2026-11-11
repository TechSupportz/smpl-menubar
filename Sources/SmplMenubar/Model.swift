import AppKit
import Observation

/// Listed from most to least visible. In the menu bar: Buried, Hidden, the dot, then Visible.
enum Section: String, CaseIterable, Identifiable {
    // Buried keeps its old stored name so saved arrangements carry over.
    case visible, hidden, buried = "alwaysHidden", disabled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .buried: "Buried"
        case .disabled: "Disabled"
        }
    }
    var subtitle: String {
        switch self {
        case .visible: "Always in the menu bar"
        case .hidden: "Shows when you hover the bar"
        case .buried: "Shows when you click the dot"
        case .disabled: "Never shown"
        }
    }
    var symbol: String {
        switch self {
        case .visible: "eye"
        case .hidden: "cursorarrow.rays"
        case .buried: "eye.slash"
        case .disabled: "nosign"
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
    /// Apps switched off in System Settings, not by this app. They show under Disabled
    /// and are left alone until dragged somewhere else.
    private var offElsewhere: Set<String> = []
    private(set) var accessError = false
    /// A switch write failed and the state it wanted isn't on screen yet. Only a successful
    /// write clears it; reading the list fine (which clears `accessError`) doesn't.
    private(set) var writePending = false

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
    /// The order you arranged apps in, across all sections; apps not in it follow, by name.
    private var order: [String] {
        didSet { Defaults.order = order }
    }
    /// Apps this app switched off, and only those. Moving one back to Visible, or quitting,
    /// switches it on again (except Disabled ones); apps you switched off yourself in
    /// System Settings are never touched.
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
        order = Defaults.order
        migrateDisabled()
        refresh()
    }

    /// The first version filed apps already switched off in System Settings under Always Hidden
    /// (now Buried), so they came back on every click. The backup taken before that first run
    /// says which they were; they move to Disabled, once.
    private func migrateDisabled() {
        guard !UserDefaults.standard.bool(forKey: "migratedDisabled") else { return }
        // No backup yet means a fresh install: nothing to move. An unreadable one is retried next launch.
        if FileManager.default.fileExists(atPath: Self.backupURL.path) {
            guard let off = ControlCenterList.switchedOff(inBackup: Self.backupURL) else { return }
            for id in off where sections[id] == .buried { sections[id] = .disabled }
        }
        UserDefaults.standard.set(true, forKey: "migratedDisabled")
    }

    private static var backupURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "smpl-menubar/controlcenter-backup.plist")
    }

    func section(of app: MenuApp) -> Section { section(of: app.id) }

    private func section(of id: String) -> Section {
        offElsewhere.contains(id) ? .disabled : sections[id] ?? .visible
    }

    func apps(in section: Section) -> [MenuApp] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return apps.enumerated()
            .filter { self.section(of: $0.element) == section }
            .sorted { (rank[$0.element.id] ?? .max, $0.offset) < (rank[$1.element.id] ?? .max, $1.offset) }
            .map(\.element)
    }

    /// Moves an app into a section, placed before `target` (an app in that section) or at its end.
    func move(_ id: String, to section: Section, before target: String? = nil) {
        guard id != target else { return }
        let oldSection = self.section(of: id)
        // Dragging an app switched off elsewhere out of Disabled hands it to this app.
        let adopting = offElsewhere.contains(id) && section != .disabled
        if adopting {
            managed.insert(id)
            offElsewhere.remove(id)
        }
        let oldOrder = apps(in: section).map(\.id)

        var full = Section.allCases.flatMap { apps(in: $0).map(\.id) }
        full = (order.filter { !full.contains($0) } + full).filter { $0 != id }
        if let target, let i = full.firstIndex(of: target) {
            full.insert(id, at: i)
        } else if let last = full.lastIndex(where: { self.section(of: $0) == section }) {
            full.insert(id, at: last + 1)
        } else {
            full.append(id)
        }
        order = full
        if adopting || oldSection != section { sections[id] = section }
        let reordered = apps(in: section).map(\.id) != oldOrder
        guard adopting || oldSection != section || reordered else { return }

        // The window updates now; the system writes wait a turn, so the drop returns
        // at once and macOS lets go of the drag image instead of holding it on screen.
        let reseat = oldSection == section && reordered
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A reorder leaves every switch as it was. Reseating first keeps apply() from placing
            // the items itself and hiding which ones moved.
            if reseat { self.reseat(section) } else { self.apply() }
            self.refresh()
        }
    }

    /// Owner bundle ID → the app's place in its section, for the menu bar layout.
    private func ownerRanks(_ section: Section) -> [String: Int] {
        var ranks: [String: Int] = [:]
        let ids = apps(in: section).map(\.id)
        // Apps not running right now keep their place after the listed ones.
        let rest = sections.filter { $0.value == section && !ids.contains($0.key) }.keys.sorted()
        for (i, id) in (ids + rest).enumerated() {
            for owner in itemOwners[id] ?? [id] where ranks[owner] == nil { ranks[owner] = i }
        }
        return ranks
    }

    /// Items only take a new place when they reappear, so after a reorder the apps that moved and
    /// are on screen now are switched off, then put back as their sections call for. They count
    /// as ours meanwhile, so quitting restores them. Hidden and Buried items that are hidden
    /// right now need nothing: every reveal places them in order.
    private func reseat(_ section: Section) {
        let moved: Set<String>
        switch section {
        case .visible:
            moved = MenuBarLayout.reorderRightOfDot(ownID: ownID, dividerName: Self.dividerName, ranks: ownerRanks(.visible))
        case .hidden where isShowing, .buried where clickShown:
            moved = placeLeftOfDot()
        default:
            return
        }
        let ids = apps(in: section).map(\.id).filter { !(itemOwners[$0] ?? [$0]).isDisjoint(with: moved) }
        cycle(ids)
    }

    /// Rebuilds the whole menu bar from Arrange: every listed app's switch is flipped to the
    /// opposite of what its section calls for, then set right a moment later, in order. Every
    /// switch really changes, so macOS redraws each item, even one stuck on screen while its saved
    /// switch already says off. Hidden, Buried and Disabled apps flash briefly as a result.
    /// Apps switched off in System Settings aren't touched.
    func resync() {
        refresh()
        guard !accessError else { return }
        _ = MenuBarLayout.reorderRightOfDot(ownID: ownID, dividerName: Self.dividerName, ranks: ownerRanks(.visible))
        placeLeftOfDot()
        let target = desiredSwitches()
        let flipped = Dictionary(uniqueKeysWithValues: apps.map(\.id)
            .filter { !offElsewhere.contains($0) }
            .map { ($0, !(target[$0] ?? true)) })
        if flipped.isEmpty {
            lastWritten = nil
            apply()
        } else {
            cycle(flipped)
        }
    }

    /// Switches `ids` off, then a moment later writes every switch from the state as it is then.
    private func cycle(_ ids: [String]) {
        cycle(Dictionary(uniqueKeysWithValues: ids.map { ($0, false) }))
    }

    /// Writes `changes`, then a moment later writes every switch from the state as it is then.
    private func cycle(_ changes: [String: Bool]) {
        guard !changes.isEmpty else { return }
        // Apps switched off count as ours meanwhile, so quitting restores them.
        managed.formUnion(changes.filter { !$0.value }.keys)
        lastWritten = nil
        if !ControlCenterList.setAllowed(changes) {
            accessError = true
            writePending = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            // Positions again, in case MenuBarAgent rewrote them as the items went; Hidden and
            // Buried are placed by write(). Every switch comes from the state as it is now, so an
            // app moved in the meantime lands in its new section, and a failed write is retried.
            _ = MenuBarLayout.reorderRightOfDot(ownID: self.ownID, dividerName: Self.dividerName, ranks: self.ownerRanks(.visible))
            self.lastWritten = nil
            self.apply()
        }
    }

    @discardableResult
    private func placeLeftOfDot() -> Set<String> {
        MenuBarLayout.place(ownID: ownID, dividerName: Self.dividerName,
                            hiddenRanks: ownerRanks(.hidden), buriedRanks: ownerRanks(.buried))
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
        ControlCenterList.backupOnce(to: Self.backupURL)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var seen = Set<String>()
        var listed: [MenuApp] = []
        var elsewhere = Set<String>()
        for entry in entries where entry.bundleID != ownID && seen.insert(entry.bundleID).inserted {
            let section = sections[entry.bundleID] ?? .visible
            if section == .visible, !entry.isAllowed, !managed.contains(entry.bundleID) {
                elsewhere.insert(entry.bundleID)
                listed.append(makeApp(entry.bundleID))
                continue
            }
            let isRunning = running.contains(entry.bundleID) || entry.itemBundleIDs.contains(where: running.contains)
            guard isRunning || section != .visible else { continue }
            listed.append(makeApp(entry.bundleID))
        }
        let byName: (MenuApp, MenuApp) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        offElsewhere = elsewhere
        apps = listed.sorted(by: byName)
    }

    /// Writes the switches the current state calls for.
    func apply() {
        write(desiredSwitches())
    }

    private func desiredSwitches() -> [String: Bool] {
        var changes: [String: Bool] = [:]
        for id in managed where (sections[id] ?? .visible) == .visible {
            changes[id] = true
        }
        for (id, section) in sections where id != ownID {
            switch section {
            case .visible: break
            case .hidden: changes[id] = hoverShown || clickShown
            case .buried: changes[id] = clickShown
            case .disabled: changes[id] = false
            }
        }
        return changes
    }

    /// On quit, switches back on every app this app switched off, except Disabled ones, which stay
    /// off like a System Settings switch. `managed` is kept, so the next launch hides them again,
    /// and a crash before this leaves enough to recover.
    func restoreForQuit() {
        let changes = Dictionary(uniqueKeysWithValues: managed.filter { sections[$0] != .disabled }.map { ($0, true) })
        accessError = !ControlCenterList.setAllowed(changes)
    }

    private func write(_ changes: [String: Bool]) {
        // Same switches as last time (e.g. hover ending while everything is shown): nothing to do.
        guard changes != lastWritten || accessError || writePending else { return }
        // Order only matters when items reappear: Hidden, then Buried, left of the dot.
        // macOS only reads the order when an item appears, so a pure hide skips it.
        if changes.values.contains(true) { placeLeftOfDot() }
        let ok = ControlCenterList.setAllowed(changes)
        accessError = !ok
        writePending = !ok
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

    /// Names and icons don't change while running; looking them up on every refresh is slow.
    private var appCache: [String: MenuApp] = [:]

    private func makeApp(_ id: String) -> MenuApp {
        if let cached = appCache[id] { return cached }
        let app = Self.lookUpApp(id)
        appCache[id] = app
        return app
    }

    private static func lookUpApp(_ id: String) -> MenuApp {
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
    static var order: [String] {
        get { UserDefaults.standard.stringArray(forKey: "order") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "order") }
    }
    static var managed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "managed") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "managed") }
    }
}
