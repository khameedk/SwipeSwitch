import os
import QuartzCore

/// Optional diagnostic log of switcher sessions: when it opened, steps, how the swipe ended, and whether the switch
/// landed. Off by default (Settings › Diagnostics). Goes to macOS's unified log on this Mac only, and contains app
/// names and positions, never keystrokes or window titles. Read it with:
///   /usr/bin/log show --last 10m --predicate 'subsystem == "io.github.khameedk.swipeswitch"'
enum SessionLog {
    private static let logger = Logger(subsystem: "io.github.khameedk.swipeswitch", category: "session")

    static var enabled: Bool { Prefs.d.bool(forKey: Prefs.Key.diagnosticLogging) }

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
