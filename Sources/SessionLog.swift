import os
import QuartzCore

/// Optional diagnostic log of switcher sessions: when it opened, steps, how the swipe ended, and whether the switch
/// landed. Off by default (Settings › Diagnostics), and turns itself off an hour after being turned on: it's meant for
/// the moment a problem is happening. Goes to macOS's unified log on this Mac only. Messages are counts, positions
/// and timings; app names are passed separately and logged only as a hash (the same app gets the same hash, so a
/// session can still be followed, but the log doesn't say which app it was). Never keystrokes, window titles or the
/// BetterTouchTool secret. Read it with:
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

    /// The message is only built when logging is on, so this costs nothing when it's off. `app` and `front` are app
    /// names: logged as hashes, never in the clear. Don't put app names, titles or secrets in `message` itself.
    static func note(_ message: @autoclosure () -> String, app: String? = nil, front: String? = nil) {
        guard enabled else { return }
        write(.default, message(), app: app, front: front)
    }

    static func problem(_ message: @autoclosure () -> String, app: String? = nil, front: String? = nil) {
        guard enabled else { return }
        write(.error, message(), app: app, front: front)
    }

    /// The names have to go straight into the logger call for macOS to hash them, hence the four variants.
    private static func write(_ type: OSLogType, _ m: String, app: String?, front: String?) {
        switch (app, front) {
        case let (a?, f?):
            logger.log(level: type, "\(m, privacy: .public) [app \(a, privacy: .private(mask: .hash))] [front \(f, privacy: .private(mask: .hash))]")
        case let (a?, nil):
            logger.log(level: type, "\(m, privacy: .public) [app \(a, privacy: .private(mask: .hash))]")
        case let (nil, f?):
            logger.log(level: type, "\(m, privacy: .public) [front \(f, privacy: .private(mask: .hash))]")
        case (nil, nil):
            logger.log(level: type, "\(m, privacy: .public)")
        }
    }

    /// Runs `body` and logs it if it took longer than `limit` seconds. Used around main-thread work that waits on other
    /// apps: while it runs, touch input waits too.
    @discardableResult
    static func timed<T>(_ label: @autoclosure () -> String, app: String? = nil, limit: Double = 0.05,
                         _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let start = CACurrentMediaTime()
        defer {
            let took = CACurrentMediaTime() - start
            if took > limit { problem("slow: \(label()) took \(Int(took * 1000)) ms", app: app) }
        }
        return try body()
    }
}
