import Foundation

enum Scope: String { case all, current }
enum Layout: String { case grid, row }
/// How the switcher appears and disappears.
enum AppearSpeed: String {
    case instant, quick, smooth
    /// Seconds for the fade out (the fade in is set in SwitcherController.begin).
    var hideDuration: Double { switch self { case .instant: return 0; case .quick: return 0.08; case .smooth: return 0.12 } }
}
enum SwipeDirection: String { case right, left }
enum SwitchMode: String { case apps, windows }
enum SortOrder: String { case recent, name }
enum HapticStrength: String {
    case light, medium, strong
    /// Trackpad actuation pattern IDs.
    var actuationID: Int32 { switch self { case .light: return 3; case .medium: return 4; case .strong: return 6 } }
}

enum Prefs {
    static let d = UserDefaults.standard

    enum Key {
        static let enabled = "enabled"
        static let fingers = "fingers"
        static let direction = "direction"
        static let step = "stepMillimetres"
        static let legacyStep = "stepDistance"
        static let activation = "activationMillimetres"
        static let bttIntegration = "bttIntegration"
        static let bttSharedSecret = "bttSharedSecret"
        static let keyboardTrigger = "keyboardTrigger"
        static let disabledSystemCommandTab = "disabledSystemCommandTab"
        static let diagnosticLogging = "diagnosticLogging"
        /// When diagnostic logging turns itself off (seconds since 1970; 0 = not running).
        static let diagnosticLoggingUntil = "diagnosticLoggingUntil"
        static let haptics = "haptics"
        static let scope = "scope"
        static let maxApps = "maxApps"
        static let layout = "layout"
        static let columns = "columns"
        static let iconSize = "iconSize"
        /// Widest the switcher may get, as a percentage of the screen's width.
        static let maxWidthPercent = "maxWidthPercent"
        static let showAllNames = "showAllNames"
        static let appearSpeed = "appearSpeed"
        static let wrap = "wrapAround"
        static let excluded = "excludedBundleIDs"
        static let didOnboard = "didOnboard"
        static let mode = "mode"
        static let includeMinimized = "includeMinimized"
        static let includeHidden = "includeHidden"
        static let sort = "sortOrder"
        static let hapticStrength = "hapticStrength"
    }

    static let defaults: [String: Any] = [
        Key.enabled: true,
        Key.fingers: 3,
        Key.direction: SwipeDirection.right.rawValue,
        Key.step: 8.0,
        Key.activation: 4.0,
        Key.bttIntegration: false,
        Key.bttSharedSecret: "",
        Key.keyboardTrigger: false,
        Key.diagnosticLogging: false,
        Key.haptics: true,
        Key.scope: Scope.all.rawValue,
        Key.maxApps: 24,
        Key.layout: Layout.grid.rawValue,
        Key.columns: 6,
        Key.iconSize: 64.0,
        Key.maxWidthPercent: 92.0,
        Key.showAllNames: false,
        Key.appearSpeed: AppearSpeed.quick.rawValue,
        Key.wrap: false,
        Key.excluded: "",
        Key.mode: SwitchMode.apps.rawValue,
        Key.includeMinimized: true,
        Key.includeHidden: true,
        Key.sort: SortOrder.recent.rawValue,
        Key.hapticStrength: HapticStrength.medium.rawValue,
    ]

    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.khameedk.swipeswitch"

    static func register() {
        // Settings saved under the app's earlier ID carry over once (except onboarding, so the
        // Accessibility prompt shows again for the new ID).
        if d.persistentDomain(forName: bundleID)?.isEmpty ?? true,
           var old = d.persistentDomain(forName: "local.swipeswitch"), !old.isEmpty {
            old.removeValue(forKey: Key.didOnboard)
            d.setPersistentDomain(old, forName: bundleID)
        }
        d.register(defaults: defaults)
        // Carry over the old width-fraction setting, measured on a 13-inch trackpad (127.4 mm wide).
        // (Check the saved values only: registered defaults would make object(forKey:) non-nil.)
        let saved = d.persistentDomain(forName: bundleID) ?? [:]
        if saved[Key.step] == nil, let old = saved[Key.legacyStep] as? Double {
            d.set((old * 127.4).rounded(), forKey: Key.step)
        }
        if saved[Key.legacyStep] != nil { d.removeObject(forKey: Key.legacyStep) }
    }
    static func reset() { for k in defaults.keys { d.removeObject(forKey: k) } }

    static var enabled: Bool { d.bool(forKey: Key.enabled) }
    static var fingerCount: Int { d.integer(forKey: Key.fingers) == 4 ? 4 : 3 }
    static var direction: SwipeDirection { SwipeDirection(rawValue: d.string(forKey: Key.direction) ?? "") ?? .right }
    /// Finger travel per step, in millimetres.
    static var stepMillimetres: Double { min(max(d.double(forKey: Key.step), 2), 30) }
    /// Finger travel that opens the switcher, in millimetres.
    static var keyboardTrigger: Bool { d.bool(forKey: Key.keyboardTrigger) }
    static var bttIntegration: Bool { d.bool(forKey: Key.bttIntegration) }
    /// Kept in the Keychain (see BTTSecret); `Key.bttSharedSecret` is only read to move an old value there.
    static var bttSharedSecret: String { BTTSecret.value }
    static var activationMillimetres: Double { min(max(d.double(forKey: Key.activation), 1), 30) }
    static var haptics: Bool { d.bool(forKey: Key.haptics) }
    static var scope: Scope { Scope(rawValue: d.string(forKey: Key.scope) ?? "") ?? .all }
    static var maxApps: Int { max(2, d.integer(forKey: Key.maxApps)) }
    static var layout: Layout { Layout(rawValue: d.string(forKey: Key.layout) ?? "") ?? .grid }
    static var columns: Int { max(1, d.integer(forKey: Key.columns)) }
    static var iconSize: Double { min(max(d.double(forKey: Key.iconSize), 24), 150) }
    static var maxWidthFraction: Double { min(max(d.double(forKey: Key.maxWidthPercent), 40), 100) / 100 }
    static var showAllNames: Bool { d.bool(forKey: Key.showAllNames) }
    static var appearSpeed: AppearSpeed { AppearSpeed(rawValue: d.string(forKey: Key.appearSpeed) ?? "") ?? .quick }
    static var mode: SwitchMode { SwitchMode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .apps }
    static var includeMinimized: Bool { d.bool(forKey: Key.includeMinimized) }
    static var includeHidden: Bool { d.bool(forKey: Key.includeHidden) }
    static var hapticStrength: HapticStrength { HapticStrength(rawValue: d.string(forKey: Key.hapticStrength) ?? "") ?? .medium }
    static var sort: SortOrder { SortOrder(rawValue: d.string(forKey: Key.sort) ?? "") ?? .recent }
    static var wrapAround: Bool { d.bool(forKey: Key.wrap) }

    static var excluded: [String] {
        get { (d.string(forKey: Key.excluded) ?? "").split(separator: "\n").map(String.init) }
        set { d.set(newValue.joined(separator: "\n"), forKey: Key.excluded) }
    }

    /// Returns a warning if macOS itself already uses the chosen swipe.
    static func gestureConflict(fingers: Int) -> String? {
        let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
        func value(_ key: String) -> Int {
            domains.compactMap { (CFPreferencesCopyAppValue(key as CFString, $0 as CFString) as? NSNumber)?.intValue }.max() ?? 0
        }
        if fingers == 3 {
            if value("TrackpadThreeFingerHorizSwipeGesture") != 0 {
                return "macOS also uses three-finger side swipes (swipe between pages or full-screen apps). Change that in Trackpad settings › More Gestures, or switch to four fingers."
            }
            if value("TrackpadThreeFingerDrag") != 0 {
                return "Three-finger drag is on, so three-finger swipes also drag windows. Turn it off in Accessibility › Pointer Control › Trackpad Options, or switch to four fingers."
            }
        } else if value("TrackpadFourFingerHorizSwipeGesture") != 0 {
            return "macOS uses four-finger side swipes to move between desktops. Turn off “Swipe between full-screen applications” in Trackpad settings › More Gestures, or switch to three fingers."
        }
        return nil
    }
}
