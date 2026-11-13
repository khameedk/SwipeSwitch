import AppKit
import ApplicationServices

enum Activator {
    /// Brings an app to the front. With Accessibility access this works reliably from a background
    /// menu bar app (and follows the app to its desktop); without it we fall back to Launch Services.
    static func activate(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }

        if AXIsProcessTrusted() {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(el, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXMainWindowAttribute as CFString, &win) == .success, let w = win {
                AXUIElementPerformAction(w as! AXUIElement, kAXRaiseAction as CFString)
            }
        }
        app.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard !app.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier,
                  let url = app.bundleURL else { return }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
    }

    /// Brings one specific window to the front, switching desktops if it lives on another one.
    static func activate(window entry: WindowEntry) {
        let app = entry.app
        let pid = app.processIdentifier
        if app.isHidden { app.unhide() }

        guard AXIsProcessTrusted() else {
            activate(app)   // without Accessibility we can only switch to the app
            return
        }
        let appEl = AXUIElementCreateApplication(pid)
        var win: AXUIElement?
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
           let list = value as? [AXUIElement] {
            win = list.first { PrivateAPI.windowID(of: $0) == entry.id }
        }
        if win == nil { win = PrivateAPI.windowElementOnAnyDesktop(pid: pid, id: entry.id) }

        if let win {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        if let win {
            // Raise again once the app (and its desktop) is in front, so this window ends up on top.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            }
        }
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
