import Foundation

/// macOS 27's per-app "Allow in the Menu Bar" switches (System Settings → Menu Bar).
///
/// Control Center keeps them in its group container as `trackedApplications`: a binary plist
/// array that alternates a key (`{bundle: {_0: id}}`) and a value (`{isAllowed, location, …}`).
/// Writes go through cfprefsd, so Control Center and MenuBarAgent see them immediately.
/// Only `isAllowed` is ever changed; everything else is written back exactly as read.
@MainActor
enum ControlCenterList {
    struct Entry {
        let bundleID: String
        let isAllowed: Bool
        /// Bundle IDs that actually own the menu bar items (can differ from the app, e.g. helpers).
        let itemBundleIDs: [String]
    }

    private static let domain = (NSHomeDirectory()
        + "/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter") as CFString
    private static let key = "trackedApplications" as CFString

    static func read() -> [Entry]? {
        guard let raw = readRaw() else { return nil }
        return stride(from: 0, to: raw.count, by: 2).compactMap { i in
            guard let id = bundleID(raw[i]), let value = raw[i + 1] as? [String: Any] else { return nil }
            let locations = (value["menuItemLocations"] as? [Any] ?? []).compactMap(bundleID)
            return Entry(bundleID: id, isAllowed: value["isAllowed"] as? Bool ?? true, itemBundleIDs: locations)
        }
    }

    /// Applies `isAllowed` changes, then reads back to confirm. If another writer (System Settings,
    /// MenuBarAgent) replaced the list in between, the changes are re-applied to the fresh copy once.
    /// Returns false if the list couldn't be read, safely written, or confirmed.
    @discardableResult
    static func setAllowed(_ changes: [String: Bool]) -> Bool {
        guard !changes.isEmpty else { return true }
        for _ in 0 ..< 2 {
            guard writeOnce(changes) else { return false }
            if let entries = read(), changes.allSatisfy({ id, want in
                entries.first { $0.bundleID == id }.map { $0.isAllowed == want } ?? true
            }) { return true }
        }
        return false
    }

    private static func writeOnce(_ changes: [String: Bool]) -> Bool {
        guard var raw = readRaw() else { return false }
        var changed = false
        for i in stride(from: 0, to: raw.count, by: 2) {
            guard let id = bundleID(raw[i]), let want = changes[id],
                  var value = raw[i + 1] as? [String: Any],
                  value["isAllowed"] as? Bool != want else { continue }
            value["isAllowed"] = want
            raw[i + 1] = value
            changed = true
        }
        guard changed else { return true }

        // Never write anything that doesn't decode back to the same number of entries.
        guard let data = try? PropertyListSerialization.data(fromPropertyList: raw, format: .binary, options: 0),
              !data.isEmpty,
              let check = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any],
              check.count == raw.count
        else { return false }

        CFPreferencesSetAppValue(key, data as CFData, domain)
        return CFPreferencesAppSynchronize(domain)
    }

    /// Saves the untouched list once, so there is always a way back.
    static func backupOnce(to url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        CFPreferencesAppSynchronize(domain)
        guard let data = CFPreferencesCopyAppValue(key, domain) as? Data, !data.isEmpty else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [key as String: data]
        (plist as NSDictionary).write(to: url, atomically: true)
    }

    private static func readRaw() -> [Any]? {
        CFPreferencesAppSynchronize(domain)
        guard let data = CFPreferencesCopyAppValue(key, domain) as? Data, !data.isEmpty,
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any],
              raw.count >= 2, raw.count.isMultiple(of: 2)
        else { return nil }
        return raw
    }

    private static func bundleID(_ any: Any) -> String? {
        ((any as? [String: Any])?["bundle"] as? [String: Any])?["_0"] as? String
    }
}
