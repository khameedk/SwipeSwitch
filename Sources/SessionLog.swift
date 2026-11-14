import os
import QuartzCore

/// Optional diagnostic log of switcher sessions: when it opened, steps, how the swipe ended, and whether the switch
/// landed. Off by default (Settings › Diagnostics), and turns itself off an hour after being turned on: it's meant for
/// the moment a problem is happening. Goes to macOS's unified log on this Mac only, and contains app
/// names and positions, never keystrokes or window titles. Read it with:
///   /usr/bin/log show --last 10m --predicate 'subsystem == "io.github.khameedk.swipeswitch"'
enum SessionLog {
    private static let logger = Logger(subsystem: "io.github.khameedk.swipeswitch", category: "session")

    /// How long logging stays on once turned on.
    static let duration: TimeInterval = 3600

    /// On, and within its hour. Past the hour it turns the setting off (Settings shows that). Safe from any thread.
    static var enabled: Bool {
        let d = Prefs.d
        guard d.bool(forKey: Prefs.Key.diagnosticLogging) else { return false }
        let now = Date().timeIntervalSince1970
        let until = d.double(forKey: Prefs.Key.diagnosticLoggingUntil)
        if until == 0 {
            // Turned on without an end time (e.g. by an earlier version): the hour starts now.
            d.set(now + duration, forKey: Prefs.Key.diagnosticLoggingUntil)
            return true
        }
        if now < until { return true }
        d.set(false, forKey: Prefs.Key.diagnosticLogging)
        d.removeObject(forKey: Prefs.Key.diagnosticLoggingUntil)
        return false
    }

    /// Called when the setting is turned on or off in Settings.
    static func settingChanged(on: Bool) {
        if on {
            Prefs.d.set(Date().timeIntervalSince1970 + duration, forKey: Prefs.Key.diagnosticLoggingUntil)
        } else {
            Prefs.d.removeObject(forKey: Prefs.Key.diagnosticLoggingUntil)
        }
    }

    /// The message is only built when logging is on, so this costs nothing when it's off.
    static func note(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let m = message()
        logger.notice("\(m, privacy: .public)")
    }

    /// Runs `body` and logs it if it took longer than `limit` seconds. Used around main-thread work that waits on other
    /// apps: while it runs, touch input waits too.
    @discardableResult
    static func timed<T>(_ label: @autoclosure () -> String, limit: Double = 0.05, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let start = CACurrentMediaTime()
        defer {
            let took = CACurrentMediaTime() - start
            if took > limit { problem("slow: \(label()) took \(Int(took * 1000)) ms") }
        }
        return try body()
    }

    static func problem(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let m = message()
        logger.error("\(m, privacy: .public)")
    }
}
