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
    static func place(ownID: String, dividerName: String, hiddenOwners: Set<String>, alwaysHiddenOwners: Set<String>) {
        CFPreferencesAppSynchronize(domain)
        let dividerKey = "status:\(ownID)::\(dividerName)"
        guard var table = CFPreferencesCopyAppValue(key, domain) as? [String: Any], !table.isEmpty,
              let dotKey = table.keys.first(where: { owner(of: $0) == ownID && $0 != dividerKey }),
              let dot = position(table[dotKey])
        else { return }

        func sorted(_ keys: [String]) -> [String] {
            keys.sorted { (position(table[$0]) ?? 0, $0) < (position(table[$1]) ?? 0, $1) }
        }
        let keys = table.keys.filter { $0 != dotKey && $0 != dividerKey }
        let hidden = sorted(keys.filter { owner(of: $0).map(hiddenOwners.contains) ?? false })
        let always = sorted(keys.filter { owner(of: $0).map(alwaysHiddenOwners.contains) ?? false })
        let managed = Set(hidden + always)
        let rest = sorted(keys.filter { !managed.contains($0) && (position(table[$0]) ?? 0) > dot })

        var changed = false
        for (offset, itemKey) in (hidden + [dividerKey] + always + rest).enumerated() {
            let value = dot + offset + 1
            if position(table[itemKey]) != value {
                table[itemKey] = value
                changed = true
            }
        }
        guard changed else { return }
        CFPreferencesSetAppValue(key, table as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func owner(of key: String) -> String? {
        guard key.hasPrefix("status:"), let sep = key.range(of: "::") else { return nil }
        return String(key[key.index(key.startIndex, offsetBy: 7) ..< sep.lowerBound])
    }

    private static func position(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }
}
