import AppKit
import ServiceManagement
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let model = Model()
    private var statusItem: NSStatusItem!
    /// Thin line between Hidden and Always Hidden, shown only while Always Hidden is.
    private var divider: NSStatusItem!
    private var window: NSWindow?
    private var hoverTimer: Timer?
    private var leftBarAt: Date?
    /// When the pointer arrived on the bar; hover reveals only after `revealDwell`,
    /// so passing through the bar doesn't cost a reveal and a hide.
    private var enteredBarAt: Date?
    /// Set by click-to-hide, so hover doesn't reveal again until the pointer has left the bar.
    private var hoverSuppressed = false
    private static let revealDwell: TimeInterval = 0.25
    private static let hideDelay: TimeInterval = 2

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        divider = NSStatusBar.system.statusItem(withLength: 9)
        divider.autosaveName = Model.dividerName
        divider.button?.image = Self.dividerImage()
        divider.isVisible = false
        updateIcon()

        model.apply()

        // Picks up Full Disk Access as soon as it's granted, and apps that start later.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasBlocked = self.model.accessError
                if wasBlocked || self.window?.isVisible == true { self.model.refresh() }
                if wasBlocked, !self.model.accessError { self.model.apply() }
            }
        }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickHover() }
        }

        if model.accessError || !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            openArrange()
        }
    }

    func applicationWillTerminate(_: Notification) {
        model.setShown(hover: false, click: false)
    }

    // MARK: Hover → Hidden section

    /// Resting on the menu bar reveals Hidden; it goes 2 seconds after the pointer leaves the bar.
    private func tickHover() {
        let onBar = Self.pointerIsOnMenuBar(revealed: model.hoverShown)
        if !onBar {
            hoverSuppressed = false
            enteredBarAt = nil
        }

        if onBar, !model.hoverShown, !hoverSuppressed {
            if let entered = enteredBarAt {
                if Date().timeIntervalSince(entered) >= Self.revealDwell {
                    enteredBarAt = nil
                    model.setShown(hover: true, click: model.clickShown)
                    updateIcon()
                }
            } else {
                enteredBarAt = Date()
            }
        }
        guard model.hoverShown else { return }
        if onBar {
            leftBarAt = nil
        } else if let left = leftBarAt {
            if Date().timeIntervalSince(left) >= Self.hideDelay {
                leftBarAt = nil
                model.setShown(hover: false, click: model.clickShown)
                updateIcon()
            }
        } else {
            leftBarAt = Date()
        }
    }

    /// Uses each screen's real bar height (taller than `NSStatusBar.thickness` beside a notch).
    /// Where the bar is hidden (full screen), only the top edge that brings it down reveals;
    /// once revealed, the usual bar strip keeps it shown.
    private static func pointerIsOnMenuBar(revealed: Bool) -> Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            guard screen.frame.contains(mouse) else { return false }
            let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
            let height = bar > 0 ? bar : (revealed ? NSStatusBar.system.thickness + 2 : 2)
            return mouse.y >= screen.frame.maxY - height
        }
    }

    // MARK: Click → everything

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        if model.clickShown {
            // One write hides both sections; hover stays off until the pointer leaves the bar.
            hoverSuppressed = true
            enteredBarAt = nil
            leftBarAt = nil
            model.setShown(hover: false, click: false)
        } else {
            model.setShown(hover: model.hoverShown, click: true)
        }
        updateIcon()
    }

    private func updateIcon() {
        statusItem.button?.image = Self.dot(filled: !model.isShowing)
        divider.isVisible = model.clickShown
    }

    private static func dividerImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 9, height: 18), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.5).set()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.5, y: rect.midY - 6, width: 1, height: 12),
                         xRadius: 0.5, yRadius: 0.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func dot(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let d: CGFloat = 8
            let circle = NSRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
            NSColor.black.set()
            if filled {
                NSBezierPath(ovalIn: circle).fill()
            } else {
                let path = NSBezierPath(ovalIn: circle.insetBy(dx: 0.75, dy: 0.75))
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Menu & window

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Arrange…", action: #selector(openArrange), keyEquivalent: ",").target = self
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    @objc private func openArrange() {
        model.refresh()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ArrangeView(model: model)))
            window.title = "smpl menubar"
            window.setContentSize(NSSize(width: 720, height: 440))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
