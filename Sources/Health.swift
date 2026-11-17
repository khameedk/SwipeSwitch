import Foundation

/// Things SwipeSwitch turned off because one of Apple's private interfaces stopped behaving as expected (most likely
/// after a macOS update). Shown in the menu and in Settings › Status. Thread-safe.
enum Health {
    enum Issue: CaseIterable {
        /// The trackpad's touch data doesn't match the layout SwipeSwitch reads, so swipes are off.
        case touchData
        /// macOS no longer accepts the lookup used to reach windows on other desktops.
        case windowLookup

        var menuLabel: String {
            switch self {
            case .touchData: return "Swipes Off: Trackpad Data Not Recognized"
            case .windowLookup: return "Can't Reach Windows on Other Desktops"
            }
        }
        var detail: String {
            switch self {
            case .touchData:
                return "Swipes are off: the trackpad data from this version of macOS isn't in the form SwipeSwitch expects, so it stopped reading it rather than guess. ⌘Tab still works if it's on. Check for a SwipeSwitch update."
            case .windowLookup:
                return "macOS no longer accepts the lookup SwipeSwitch uses to reach windows on other desktops. Switching to those windows brings their app forward instead. Check for a SwipeSwitch update."
            }
        }
    }

    private static let lock = NSLock()
    private static var issues = Set<Issue>()

    static func report(_ issue: Issue) {
        lock.lock()
        let isNew = issues.insert(issue).inserted
        lock.unlock()
        guard isNew else { return }
        NSLog("SwipeSwitch: turned off: \(issue.menuLabel)")
        SessionLog.problem("turned off: \(issue.menuLabel)")
    }

    static func has(_ issue: Issue) -> Bool { lock.lock(); defer { lock.unlock() }; return issues.contains(issue) }

    static var current: [Issue] { Issue.allCases.filter(has) }
    static var warnings: [String] { current.map(\.detail) }
}
