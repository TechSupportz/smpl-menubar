import Foundation

/// macOS 27's saved menu bar order: `TrailingItemPreferredPositions` in MenuBarAgent's group
/// container, keyed `status:<owner bundle ID>::<item name>`. A higher number sits further left.
/// macOS uses it when an item (re)appears, so setting it before a reveal decides where items land.
@MainActor
enum MenuBarLayout {
    private static let domain = (NSHomeDirectory()
        + "/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar") as CFString
    private static let key = "TrailingItemPreferredPositions" as CFString

    /// Lays out, right to left: everything already right of the dot, the dot, Hidden, Buried,
    /// then whatever else was left of the dot. Items right of the dot are never touched.
    /// Ranks map an owner bundle ID to its place in Arrange (0 = leftmost); an owner's own items keep their order.
    /// The divider (our second item) goes between Hidden and Buried.
    /// Reads back after writing; if MenuBarAgent replaced the table in between, lays out the fresh copy once more.
    /// Returns the owners whose items it moved.
    @discardableResult
    static func place(ownID: String, dividerName: String, hiddenRanks: [String: Int], buriedRanks: [String: Int]) -> Set<String> {
        var moved = Set<String>()
        for _ in 0 ..< 2 {
            let written = placeOnce(ownID: ownID, dividerName: dividerName,
                                    hiddenRanks: hiddenRanks, buriedRanks: buriedRanks)
            moved.formUnion(written.keys.compactMap(owner(of:)))
            guard !written.isEmpty else { break }
            CFPreferencesAppSynchronize(domain)
            let table = CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
            if written.allSatisfy({ position(table[$0.key]) == $0.value }) { break }
        }
        return moved
    }

    /// Returns the positions it wrote, empty if nothing needed changing.
    private static func placeOnce(ownID: String, dividerName: String, hiddenRanks: [String: Int], buriedRanks: [String: Int]) -> [String: Int] {
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
        // Written right to left from the dot, so the last in Arrange comes first.
        func ranked(_ ranks: [String: Int]) -> [String] {
            keys.compactMap { key in owner(of: key).flatMap { ranks[$0] }.map { (key, $0) } }
                .sorted { ($1.1, position(table[$0.0]) ?? 0, $0.0) < ($0.1, position(table[$1.0]) ?? 0, $1.0) }
                .map(\.0)
        }
        let hidden = ranked(hiddenRanks)
        let always = ranked(buriedRanks)
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

    /// Reorders items right of the dot to follow `ranks`, reusing the slots they already hold.
    /// Returns the owners whose items moved; they only land there once they reappear.
    static func reorderRightOfDot(ownID: String, dividerName: String, ranks: [String: Int]) -> Set<String> {
        CFPreferencesAppSynchronize(domain)
        let dividerKey = "status:\(ownID)::\(dividerName)"
        guard var table = CFPreferencesCopyAppValue(key, domain) as? [String: Any],
              let dotKey = table.keys.first(where: { owner(of: $0) == ownID && $0 != dividerKey }),
              let dot = position(table[dotKey])
        else { return [] }
        let items = table.keys.compactMap { key -> (key: String, rank: Int, pos: Int)? in
            guard let rank = owner(of: key).flatMap({ ranks[$0] }),
                  let pos = position(table[key]), pos < dot else { return nil }
            return (key, rank, pos)
        }
        // Leftmost in Arrange takes the highest slot.
        let slots = items.map(\.pos).sorted(by: >)
        let ordered = items.sorted { ($0.rank, -$0.pos, $0.key) < ($1.rank, -$1.pos, $1.key) }
        var moved = Set<String>()
        for (item, slot) in zip(ordered, slots) where item.pos != slot {
            table[item.key] = slot
            if let owner = owner(of: item.key) { moved.insert(owner) }
        }
        guard !moved.isEmpty else { return [] }
        CFPreferencesSetAppValue(key, table as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        return moved
    }

    private static func owner(of key: String) -> String? {
        guard key.hasPrefix("status:"), let sep = key.range(of: "::") else { return nil }
        return String(key[key.index(key.startIndex, offsetBy: 7) ..< sep.lowerBound])
    }

    private static func position(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }
}
