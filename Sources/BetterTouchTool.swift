import AppKit
import CoreServices

/// Optional: lets BetterTouchTool know while the switcher is open, so BTT gestures can pause.
/// Sets the BTT variable `swipeswitch_active` to 1 on open and 0 on close.
/// Does nothing unless the user turns it on and BTT is already running (we never launch BTT).
///
/// The variable is set with BTT's AppleScript command, sent as an Apple Event straight to BTT. That needs a one-time
/// macOS "control BetterTouchTool" permission. Without it we fall back to BTT's btt:// link, which works but goes
/// through Launch Services; a link opened just as an app is being switched to can make macOS hand the front back to
/// the previous app for a moment, so the switched-to window flickers.
enum BetterTouchTool {
    static let variable = "swipeswitch_active"
    private static let bundleID = "com.hegenberg.BetterTouchTool"
    /// Events go out one at a time, in order, off the main thread (a send can wait on the permission prompt).
    private static let queue = DispatchQueue(label: "io.github.khameedk.swipeswitch.btt")

    /// Whether SwipeSwitch may control BTT. `ask`: show macOS's prompt if it hasn't been answered (blocks until it is,
    /// so call off the main thread).
    static func hasPermission(ask: Bool) -> Bool { permission(ask: ask) == noErr }

    /// BTT's own "Allow external BetterTouchTool Scripting" setting, if it can be read.
    static var externalScriptingAllowed: Bool? {
        CFPreferencesCopyAppValue("BTTAllowExternalScripting" as CFString, bundleID as CFString) as? Bool
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// `wait`: send before returning (used when quitting, so the reset isn't lost).
    static func setActive(_ active: Bool, wait: Bool = false) {
        guard Prefs.bttIntegration, isRunning else { return }
        let value = active ? "1" : "0"
        if wait {
            let secret = queue.sync { Prefs.bttSharedSecret }
            let sent = queue.sync { permission(ask: false) == noErr && sendEvent(value: value, secret: secret) }
            if !sent { openLink(value: value, secret: secret) }
            return
        }
        queue.async {
            let secret = Prefs.bttSharedSecret   // read here, off the main thread (it comes from the Keychain)
            if permission(ask: true) == noErr, sendEvent(value: value, secret: secret) { return }
            DispatchQueue.main.async { openLink(value: value, secret: secret) }
        }
    }

    /// noErr when allowed; errAEEventNotPermitted when the user said no.
    private static func permission(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(errAEEventNotPermitted) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    }

    private static func fourCC(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    /// BTT's `set_string_variable "name" to "value" [shared_secret "…"]`, without waiting for a reply.
    private static func sendEvent(value: String, secret: String) -> Bool {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: fourCC("Bttt"), eventID: fourCC("SetV"),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: variable), forKeyword: keyDirectObject)
        event.setParam(NSAppleEventDescriptor(string: value), forKeyword: fourCC("bTpV"))
        if !secret.isEmpty { event.setParam(NSAppleEventDescriptor(string: secret), forKeyword: fourCC("btSs")) }
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 1)
            return true
        } catch {
            SessionLog.problem("BTT: Apple Event failed (\(error.localizedDescription)), using the btt:// link")
            return false
        }
    }

    /// Sends one BTT scripting command and waits for its text reply. `params` maps four-letter parameter codes from
    /// BTT's scripting dictionary to values. Call off the main thread. Throws if the event can't be delivered.
    static func command(_ eventID: String, direct: String? = nil, params: [String: String] = [:]) throws -> String {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: fourCC("Bttt"), eventID: fourCC(eventID),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let direct { event.setParam(NSAppleEventDescriptor(string: direct), forKeyword: keyDirectObject) }
        for (code, value) in params { event.setParam(NSAppleEventDescriptor(string: value), forKeyword: fourCC(code)) }
        let secret = Prefs.bttSharedSecret
        if !secret.isEmpty { event.setParam(NSAppleEventDescriptor(string: secret), forKeyword: fourCC("btSs")) }
        let reply = try event.sendEvent(options: [.waitForReply], timeout: 10)
        return reply.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? ""
    }

    private static func openLink(value: String, secret: String) {
        var parts = URLComponents(string: "btt://set_string_variable/")!
        parts.queryItems = [URLQueryItem(name: "variable_name", value: variable), URLQueryItem(name: "to", value: value)]
        if !secret.isEmpty { parts.queryItems?.append(URLQueryItem(name: "shared_secret", value: secret)) }
        guard let url = parts.url else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false   // stay in the background
        NSWorkspace.shared.open(url, configuration: cfg)
    }
}
