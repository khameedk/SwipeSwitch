import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var tracker: AppTracker!
    private var windowTracker: WindowTracker!
    private var switcher: SwitcherController!
    private let recognizer = SwipeGestureRecognizer()
    private var settingsWindow: NSWindow?
    private var devicePoll: Timer?
    private var demoCancels = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        tracker = AppTracker()
        windowTracker = WindowTracker()
        switcher = SwitcherController(apps: tracker, windows: windowTracker)
        setupStatusItem()

        recognizer.onBegin = { [weak self] in
            guard let self = self else { return false }
            self.recognizer.allowVertical = Prefs.layout == .grid
            return self.switcher.begin()
        }
        recognizer.onStep = { [weak self] dx, dy in self?.switcher.step(dx: dx, dy: dy) }
        recognizer.onEnd = { [weak self] in
            guard let self = self else { return }
            if self.demoCancels { self.switcher.cancel() } else { self.switcher.commit() }
        }

        let mt = MultitouchMonitor.shared
        mt.onFrame = { [weak self] f in self?.recognizer.handle(f) }
        let n = mt.start()
        NSLog("SwipeSwitch: multitouch loaded=\(mt.isLoaded) devices=\(n) accessibility=\(AXIsProcessTrusted())")

        // Touch devices go quiet after sleep, and a Magic Trackpad can connect at any time.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MultitouchMonitor.shared.restart() }
        }
        devicePoll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, !self.recognizer.isActive else { return }
            if mt.attachedDeviceCount() != mt.deviceCount { mt.restart() }
        }

        if !Prefs.d.bool(forKey: Prefs.Key.didOnboard) {
            Prefs.d.set(true, forKey: Prefs.Key.didOnboard)
            showSettings()
            if !AXIsProcessTrusted() { Activator.promptForAccessibility() }
        }

        if let demo = ProcessInfo.processInfo.environment["SWIPESWITCH_DEMO"] {
            demoCancels = demo != "commit"
            runDemo()
        }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "SwipeSwitch")
            img?.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        statusItem.button?.appearsDisabled = !Prefs.enabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = Prefs.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        let modeHeader = NSMenuItem(title: "Switch between", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)
        for (title, mode) in [("Apps", SwitchMode.apps), ("Windows", SwitchMode.windows)] {
            let item = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = Prefs.mode == mode ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }
        let sortHeader = NSMenuItem(title: "Sort by", action: nil, keyEquivalent: "")
        sortHeader.isEnabled = false
        menu.addItem(sortHeader)
        for (title, order) in [("Last Active", SortOrder.recent), ("Name", SortOrder.name)] {
            let item = NSMenuItem(title: title, action: #selector(setSort(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = order.rawValue
            item.state = Prefs.sort == order ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }
        let header = NSMenuItem(title: "Show from", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (title, scope) in [("All Desktops", Scope.all), ("Current Desktop", Scope.current)] {
            let item = NSMenuItem(title: title, action: #selector(setScope(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scope.rawValue
            item.state = Prefs.scope == scope ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }
        let layoutHeader = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        layoutHeader.isEnabled = false
        menu.addItem(layoutHeader)
        for (title, layout) in [("Grid", Layout.grid), ("Single Row", Layout.row)] {
            let item = NSMenuItem(title: title, action: #selector(setLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.rawValue
            item.state = Prefs.layout == layout ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if MultitouchMonitor.shared.deviceCount == 0 {
            let none = NSMenuItem(title: "No trackpad detected", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        if !AXIsProcessTrusted() {
            let ax = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccessibility), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SwipeSwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleEnabled() {
        Prefs.d.set(!Prefs.enabled, forKey: Prefs.Key.enabled)
        updateStatusIcon()
    }

    @objc private func setScope(_ sender: NSMenuItem) {
        Prefs.d.set(sender.representedObject as? String, forKey: Prefs.Key.scope)
    }

    @objc private func setSort(_ sender: NSMenuItem) {
        Prefs.d.set(sender.representedObject as? String, forKey: Prefs.Key.sort)
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        Prefs.d.set(sender.representedObject as? String, forKey: Prefs.Key.mode)
    }

    @objc private func setLayout(_ sender: NSMenuItem) {
        Prefs.d.set(sender.representedObject as? String, forKey: Prefs.Key.layout)
    }

    @objc private func grantAccessibility() {
        Activator.promptForAccessibility()
        Activator.openAccessibilitySettings()
    }

    @objc private func openSettings() { showSettings() }

    private func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(status: SettingsStatus()))
            let w = NSWindow(contentViewController: host)
            w.title = "SwipeSwitch Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                self?.updateStatusIcon()
            }
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Demo (SWIPESWITCH_DEMO=1 to preview without touching the trackpad)

    private func runDemo() {
        let dev: UInt = 0xDE30
        let n = Prefs.fingerCount
        let size = MultitouchMonitor.fallbackSize   // the demo device reports no size
        let step = Prefs.stepMillimetres / size.width
        let stepY = Prefs.stepMillimetres / size.height
        let hold = Int((Double(ProcessInfo.processInfo.environment["SWIPESWITCH_DEMO_HOLD"] ?? "") ?? 2.5) * 100)
        var frames: [TouchFrame] = []
        var x = 0.30, y = 0.5
        for _ in 0..<20 { frames.append(TouchFrame(device: dev, count: n, x: x, y: y)) }
        let target = x + Prefs.activationMillimetres / size.width + step * 3.5
        while x < target { x += 0.006; frames.append(TouchFrame(device: dev, count: n, x: x, y: y)) }
        let snap1 = frames.count + 60
        for _ in 0..<hold { frames.append(TouchFrame(device: dev, count: n, x: x, y: y)) }
        let yTarget = y - stepY * 1.2
        while y > yTarget { y -= 0.006; frames.append(TouchFrame(device: dev, count: n, x: x, y: y)) }
        for _ in 0..<hold { frames.append(TouchFrame(device: dev, count: n, x: x, y: y)) }
        let snap2 = frames.count - hold + 60
        frames.append(TouchFrame(device: dev, count: 0, x: 0, y: 0))

        let dir = ProcessInfo.processInfo.environment["SWIPESWITCH_SNAPSHOT_DIR"]
        if let dir = dir {
            showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let view = self?.settingsWindow?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/settings.png"))
            }
        }
        var i = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] t in
                guard let self = self, i < frames.count else { t.invalidate(); return }
                self.recognizer.simulate(frames[i])
                if let dir = dir, let k = [snap1, snap2].firstIndex(of: i) {
                    self.switcher.snapshot(to: "\(dir)/overlay\(k + 1).png")
                }
                i += 1
            }
        }
    }
}
