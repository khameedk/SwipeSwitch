import AppKit

/// The app in front, counting a switch SwipeSwitch has just made that macOS hasn't finished yet. Without this, a
/// quick second swipe would still see the old app in front and start on the app you'd just switched to.
/// Main thread only.
enum FrontApp {
    private static var pending: (pid: pid_t, at: Double)?
    /// A switch that hasn't landed by then is treated as failed.
    private static let pendingMaxAge = 1.0

    static func switching(to pid: pid_t) { pending = (pid, CACurrentMediaTime()) }
    /// Any app activation (the switch landing, or the user picking another app) ends the wait.
    static func activated() { pending = nil }

    static var switchPending: Bool {
        guard let p = pending else { return false }
        if CACurrentMediaTime() - p.at < pendingMaxAge { return true }
        pending = nil
        return false
    }
    static var pid: pid_t? {
        if switchPending, let p = pending { return p.pid }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

/// Keeps apps in most-recently-used order and answers "which apps should the switcher show?".
final class AppTracker {
    private var mru: [pid_t] = []
    private let myPID = ProcessInfo.processInfo.processIdentifier

    init() {
        seed()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            FrontApp.activated()
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.bump(app.processIdentifier)
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.mru.removeAll { $0 == app.processIdentifier }
        }
    }

    private func bump(_ pid: pid_t) {
        mru.removeAll { $0 == pid }
        mru.insert(pid, at: 0)
    }

    /// Before we've seen any activations, approximate recency from window stacking order.
    private func seed() {
        var order: [pid_t] = []
        func add(_ p: pid_t) { if !order.contains(p) { order.append(p) } }
        if let front = NSWorkspace.shared.frontmostApplication { add(front.processIdentifier) }
        Self.windowOwnerPIDs(currentSpaceOnly: true).forEach(add)
        Self.windowOwnerPIDs(currentSpaceOnly: false).forEach(add)
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.forEach { add($0.processIdentifier) }
        mru = order
    }

    /// PIDs owning normal windows, front-to-back.
    static func windowOwnerPIDs(currentSpaceOnly: Bool) -> [pid_t] {
        let opts: CGWindowListOption = currentSpaceOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [pid_t] = []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            if let b = w[kCGWindowBounds as String] as? [String: Any],
               let width = (b["Width"] as? NSNumber)?.doubleValue,
               let height = (b["Height"] as? NSNumber)?.doubleValue,
               width < 60 || height < 60 { continue }
            if let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 { continue }
            if !out.contains(pid) { out.append(pid) }
        }
        return out
    }

    /// Apps in most-recently-used order, limited to those that own one of `windowOwners` (apps with no real
    /// window are never shown). `firstIsCurrent` says whether item 0 is the app already in front.
    /// `owners` are the apps that own a real window (already known to be regular, running apps); only they
    /// appear. Avoids scanning every running process, which is slow.
    func candidates(owners: [pid_t: NSRunningApplication]) -> (apps: [NSRunningApplication], firstIsCurrent: Bool) {
        let byPID = owners
        for pid in owners.keys.sorted() where !mru.contains(pid) { mru.append(pid) }

        let frontPID = FrontApp.pid
        if let f = frontPID, let i = mru.firstIndex(of: f), i != 0 { mru.remove(at: i); mru.insert(f, at: 0) }

        let ordered = mru.compactMap { byPID[$0] }
        return (Array(ordered.prefix(Prefs.maxApps)), ordered.first?.processIdentifier == frontPID)
    }
}
