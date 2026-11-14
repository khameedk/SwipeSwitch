import AppKit
import ApplicationServices

enum Activator {
    /// Accessibility calls to the app being switched to. They wait for that app to answer, which can take hundreds of
    /// milliseconds while it's coming to the front; on the main thread that would hold up touch input (the next
    /// swipe's overlay could open late, or not be drawn at all). One serial queue keeps them in order.
    static let axQueue = DispatchQueue(label: "io.github.khameedk.swipeswitch.activate", qos: .userInteractive)

    /// Brings an app to the front. With Accessibility access this works reliably from a background
    /// menu bar app (and follows the app to its desktop); without it we fall back to Launch Services.
    static func activate(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        stopWaitingForActivation()
        switchID &+= 1
        let thisSwitch = switchID

        func activateNow() {
            guard switchID == thisSwitch else { return }   // a newer switch took over
            app.activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard switchID == thisSwitch, !app.isTerminated,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier,
                      let url = app.bundleURL else { return }
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            }
        }
        guard AXIsProcessTrusted() else { activateNow(); return }
        axQueue.async {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(el, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXMainWindowAttribute as CFString, &win) == .success, let w = win {
                AXUIElementPerformAction(w as! AXUIElement, kAXRaiseAction as CFString)
            }
            DispatchQueue.main.async { activateNow() }
        }
    }

    /// The window being switched to, found on `axQueue` and only used there.
    private final class Target: @unchecked Sendable { var window: AXUIElement? }

    /// Brings one specific window to the front, switching desktops if it lives on another one.
    /// The steps that talk to the app run in order on `axQueue`; activating and the timers stay on the main thread.
    static func activate(window entry: WindowEntry) {
        let app = entry.app
        let pid = app.processIdentifier
        if app.isHidden { app.unhide() }

        guard AXIsProcessTrusted() else {
            activate(app)   // without Accessibility we can only switch to the app
            return
        }
        let appEl = AXUIElementCreateApplication(pid)
        let target = Target()

        // Ask macOS rather than trusting the app's activation event: apps sometimes come to the front and then lose it
        // again a moment later, and the safety net below needs to catch that.
        func inFront() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        stopWaitingForActivation()
        switchID &+= 1
        let thisSwitch = switchID
        let sameApp = inFront()

        if !sameApp {
            // When the app comes to the front it may first show the window it had on top. Raise ours once, at that
            // moment, and only if it isn't already the focused window, so the window order changes as little as possible.
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { note in
                let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard activated?.processIdentifier == pid, switchID == thisSwitch else { return }
                stopWaitingForActivation()
                axQueue.async {
                    guard let win = target.window else { return }
                    if isFocused(win, in: appEl) {
                        SessionLog.note("raise: app came to front with the window already on top")
                    } else {
                        SessionLog.note("raise: app came to front showing another window, raising once")
                        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                    }
                }
            }
            // Don't keep listening if the app never comes to the front (the safety net below handles that).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if switchID == thisSwitch { stopWaitingForActivation() }
            }
        }

        // Safety net: apps can ignore activation requests from a background app (Chrome does, roughly 1 in 4 times in
        // testing). If the app isn't in front after 0.3 s, ask again; if it still isn't 0.3 s later, fall back to
        // Launch Services like apps mode. Each check is a single "which app is in front?" lookup. A newer switch
        // cancels this one's safety net.
        func scheduleSafetyNet() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard switchID == thisSwitch, !app.isTerminated, !inFront() else { return }
                SessionLog.note("safety net: \(app.localizedName ?? "?") not in front after 0.3 s, asking again")
                axQueue.async {
                    if let win = target.window { AXUIElementPerformAction(win, kAXRaiseAction as CFString) }
                    AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                    DispatchQueue.main.async { if switchID == thisSwitch { app.activate() } }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard switchID == thisSwitch, !app.isTerminated, !inFront(), let url = app.bundleURL else { return }
                    SessionLog.note("safety net: still not in front, using Launch Services")
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
                        axQueue.asyncAfter(deadline: .now() + 0.1) {
                            if let win = target.window { AXUIElementPerformAction(win, kAXRaiseAction as CFString) }
                        }
                    }
                }
            }
        }

        axQueue.async {
            var win: AXUIElement?
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
               let list = value as? [AXUIElement] {
                win = list.first { PrivateAPI.windowID(of: $0) == entry.id }
            }
            if win == nil { win = PrivateAPI.windowElementOnAnyDesktop(pid: pid, id: entry.id) }
            target.window = win
            if let win {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            }
            if sameApp {
                // Another window of the app that's already in front: the raise above is all it takes.
                SessionLog.note("raise: same app, raised directly")
                return
            }
            AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            DispatchQueue.main.async {
                guard switchID == thisSwitch else { return }   // a newer switch took over
                app.activate()
                scheduleSafetyNet()
            }
        }
    }

    /// Counts switches, so a newer switch cancels an older one's pending follow-ups. Main thread only.
    private static var switchID = 0
    /// Listens for the target app coming to the front during a window switch (at most one at a time).
    private static var activationObserver: NSObjectProtocol?

    private static func stopWaitingForActivation() {
        if let o = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            activationObserver = nil
        }
    }

    private static func isFocused(_ win: AXUIElement, in appEl: AXUIElement) -> Bool {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let f = focused else { return false }
        return CFEqual(f, win)
    }

    static func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
