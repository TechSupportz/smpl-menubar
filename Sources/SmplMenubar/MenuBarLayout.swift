import Foundation

/// macOS 27's saved menu bar order: `TrailingItemPreferredPositions` in MenuBarAgent's group
/// container, keyed `status:<owner bundle ID>::<item name>`. A higher number sits further left.
/// macOS uses it when an item (re)appears, so setting it before a reveal decides where items land.
@MainActor
enum MenuBarLayout {
    private static let domain = (NSHomeDirectory()
        + "/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar") as CFString
    private static let key = "TrailingItemPreferredPositions" as CFString

    /// Lays out, right to left: everything already right of the dot, the dot, Hidden, Always Hidden,
    /// then whatever else was left of the dot. Items right of the dot are never touched,
    /// and relative order inside each group is kept.
    /// The divider (our second item) goes between Hidden and Always Hidden.
    /// Reads back after writing; if MenuBarAgent replaced the table in between, lays out the fresh copy once more.
    static func place(ownID: String, dividerName: String, hiddenOwners: Set<String>, alwaysHiddenOwners: Set<String>) {
        for _ in 0 ..< 2 {
            let written = placeOnce(ownID: ownID, dividerName: dividerName,
                                    hiddenOwners: hiddenOwners, alwaysHiddenOwners: alwaysHiddenOwners)
            guard !written.isEmpty else { return }
            CFPreferencesAppSynchronize(domain)
            let table = CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
            if written.allSatisfy({ position(table[$0.key]) == $0.value }) { return }
        }
    }

    /// Returns the positions it wrote, empty if nothing needed changing.
    private static func placeOnce(ownID: String, dividerName: String, hiddenOwners: Set<String>, alwaysHiddenOwners: Set<String>) -> [String: Int] {
        CFPreferencesAppSynchronize(domain)
        let dividerKey = "status:\(ownID)::\(dividerName)"
        guard var table = CFPreferencesCopyAppValue(key, domain) as? [String: Any], !table.isEmpty,
              let dotKey = table.keys.first(where: { owner(of: $0) == ownID && $0 != dividerKey }),
              let dot = position(table[dotKey])
        else { return [:] }

        func sorted(_ keys: [String]) -> [String] {
            keys.sorted { (position(table[$0]) ?? 0, $0) < (position(table[$1]) ?? 0, $1) }
        }
        let keys = table.keys.filter { $0 != dotKey && $0 != dividerKey }
        let hidden = sorted(keys.filter { owner(of: $0).map(hiddenOwners.contains) ?? false })
        let always = sorted(keys.filter { owner(of: $0).map(alwaysHiddenOwners.contains) ?? false })
        let managed = Set(hidden + always)
        let rest = sorted(keys.filter { !managed.contains($0) && (position(table[$0]) ?? 0) > dot })

        var written: [String: Int] = [:]
        for (offset, itemKey) in (hidden + [dividerKey] + always + rest).enumerated() {
            let value = dot + offset + 1
            if position(table[itemKey]) != value {
                table[itemKey] = value
                written[itemKey] = value
            }
        }
        guard !written.isEmpty else { return [:] }
        CFPreferencesSetAppValue(key, table as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        return written
    }

    private static func owner(of key: String) -> String? {
        guard key.hasPrefix("status:"), let sep = key.range(of: "::") else { return nil }
        return String(key[key.index(key.startIndex, offsetBy: 7) ..< sep.lowerBound])
    }

    private static func position(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }
}
