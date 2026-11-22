import AppKit

/// System menu bar items (Wi‑Fi, Sound, Focus…): Control Center modules, not apps, so they have no
/// "Allow in the Menu Bar" switch. Their switch is System Settings → Control Center → "Show in Menu
/// Bar", stored per host in `com.apple.controlcenter` as a number per module; bit 0x2 means shown.
/// Control Center picks up writes at once. In the menu bar order they're keyed `module:<name>`,
/// which is also their ID here.
@MainActor
enum ControlCenterModules {
    static let prefix = "module:"
    private static let domain = "com.apple.controlcenter" as CFString
    private static let shownBit = 0x2
    /// Not in the menu bar; what System Settings writes for "Don't Show".
    private static let hiddenValue = 8
    /// "Always Show", for a module this app never saw shown.
    private static let defaultShownValue = 18

    /// The modules that can sit in the menu bar on their own: title and symbol.
    private static let known: [String: (title: String, symbol: String)] = [
        "WiFi": ("Wi‑Fi", "wifi"),
        "Bluetooth": ("Bluetooth", "dot.radiowaves.left.and.right"),
        "AirDrop": ("AirDrop", "antenna.radiowaves.left.and.right"),
        "FocusModes": ("Focus", "moon.fill"),
        "StageManager": ("Stage Manager", "squares.leading.rectangle"),
        "ScreenMirroring": ("Screen Mirroring", "rectangle.on.rectangle"),
        "Display": ("Display", "sun.max.fill"),
        "Sound": ("Sound", "speaker.wave.2.fill"),
        "NowPlaying": ("Now Playing", "play.fill"),
        "Battery": ("Battery", "battery.100percent"),
        "KeyboardBrightness": ("Keyboard Brightness", "light.max"),
        "UserSwitcher": ("Fast User Switching", "person.crop.circle"),
        "MusicRecognition": ("Music Recognition", "shazam.logo.fill"),
    ]

    static func isModule(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// Every known module with a saved setting, by ID, and whether it's shown.
    static func read() -> [String: Bool] {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        var result: [String: Bool] = [:]
        for name in known.keys {
            guard let value = value(of: name) else { continue }
            result[prefix + name] = value & shownBit != 0
        }
        return result
    }

    /// Shows or hides modules, then reads back to confirm. A module's own "shown" value is kept the
    /// first time it's hidden, so showing it again restores, say, "Show When Active".
    @discardableResult
    static func setShown(_ changes: [String: Bool]) -> Bool {
        guard !changes.isEmpty else { return true }
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        var saved = savedValues
        var wrote = false
        for (id, show) in changes {
            let name = String(id.dropFirst(prefix.count))
            guard known[name] != nil else { continue }
            let current = value(of: name)
            if current.map({ $0 & shownBit != 0 }) == show { continue }
            let new: Int
            if show {
                new = saved[name] ?? defaultShownValue
            } else {
                if let current, current & shownBit != 0 { saved[name] = current }
                new = hiddenValue
            }
            CFPreferencesSetValue(name as CFString, new as CFNumber, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            wrote = true
        }
        savedValues = saved
        guard wrote else { return true }
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else { return false }
        let now = read()
        // A module that can't be read back counts as not confirmed.
        return changes.allSatisfy { id, show in now[id] == show }
    }

    /// A copy of a module's icon at menu size.
    static func menuIcon(_ app: MenuApp) -> NSImage {
        let image = app.icon.copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func makeApp(_ id: String) -> MenuApp {
        let name = String(id.dropFirst(prefix.count))
        let info = known[name] ?? (name, "switch.2")
        return MenuApp(id: id, name: info.title, icon: tile(symbol: info.symbol))
    }

    private static func value(of name: String) -> Int? {
        (CFPreferencesCopyValue(name as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? NSNumber)?.intValue
    }

    private static var savedValues: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "moduleShownValues") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "moduleShownValues") }
    }

    /// A white symbol on a grey rounded square, like System Settings' Control Center icons.
    private static func tile(symbol: String) -> NSImage {
        let size = NSSize(width: 44, height: 44)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.systemGray.setFill()
            // Drawn relative to the rect, so a copy resized for a menu stays in proportion.
            let unit = rect.height / 44
            NSBezierPath(roundedRect: rect.insetBy(dx: 2 * unit, dy: 2 * unit), xRadius: 10 * unit, yRadius: 10 * unit).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 22 * unit, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let s = image.size
                image.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
            }
            return true
        }
    }
}
