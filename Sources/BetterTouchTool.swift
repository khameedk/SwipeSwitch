import AppKit

/// Optional: lets BetterTouchTool know while the switcher is open, so BTT gestures can pause.
/// Sets the BTT variable `swipeswitch_active` to 1 on open and 0 on close, via BTT's btt:// links.
/// Does nothing unless the user turns it on and BTT is already running (a btt:// link would launch it).
enum BetterTouchTool {
    static let variable = "swipeswitch_active"
    private static let bundleID = "com.hegenberg.BetterTouchTool"

    static func setActive(_ active: Bool) {
        guard Prefs.bttIntegration,
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        var parts = URLComponents(string: "btt://set_string_variable/")!
        parts.queryItems = [URLQueryItem(name: "variable_name", value: variable),
                            URLQueryItem(name: "to", value: active ? "1" : "0")]
        let secret = Prefs.bttSharedSecret
        if !secret.isEmpty { parts.queryItems?.append(URLQueryItem(name: "shared_secret", value: secret)) }
        guard let url = parts.url else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false   // stay in the background
        NSWorkspace.shared.open(url, configuration: cfg)
    }
}
