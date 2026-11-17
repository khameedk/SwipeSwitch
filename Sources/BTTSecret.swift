import Foundation
import Security

/// SwipeSwitch's copy of BetterTouchTool's shared secret (the one typed into Settings › BetterTouchTool), sent with
/// each BTT command. Kept in the login Keychain as SwipeSwitch's own item, never in the preferences file (which any
/// program running as you can read). BTT keeps its own copy in its own Keychain item; this doesn't touch that.
///
/// Read once while the BetterTouchTool option is on (the first read after an update may show a Keychain prompt), then
/// served from memory; turning the option off drops the copy in memory. Thread-safe.
enum BTTSecret {
    private static let service = "io.github.khameedk.swipeswitch.btt-shared-secret"
    private static let account = "BetterTouchTool"
    private static let lock = NSLock()
    private static var cached: String?
    private static var lastProblem: String?

    /// The secret, or "" if there is none (or the Keychain wouldn't give it out; then BTT commands go without it,
    /// and BTT turns them down if it requires one). Can wait on a Keychain prompt: call off the main thread.
    static var value: String {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        #if SWIPESWITCH_DEV
        // Test runs of a --dev build are a different binary, so the Keychain would ask for your password each time.
        if ProcessInfo.processInfo.environment["SWIPESWITCH_NO_KEYCHAIN"] != nil { cached = ""; return "" }
        #endif
        let v = read()
        cached = v
        return v
    }

    /// The secret if it has been read already, else nil. Never waits, so Settings can draw it on the main thread.
    static var loaded: String? { lock.lock(); defer { lock.unlock() }; return cached }

    /// What went wrong reading or saving the secret, if anything (shown in Settings).
    static var problem: String? { lock.lock(); defer { lock.unlock() }; return lastProblem }

    /// At launch and whenever settings change: matches the copy in memory to the BetterTouchTool option. When it's on,
    /// reads the secret in the background (so a Keychain prompt never holds up the main thread); when it's off, drops it.
    static func sync() {
        if Prefs.bttIntegration {
            if loaded == nil { DispatchQueue.global(qos: .utility).async { _ = value } }
        } else {
            lock.lock(); cached = nil; lastProblem = nil; lock.unlock()
        }
    }

    /// Versions before 1.3 kept the secret in the preferences file. Deletes any such copy (it's never read).
    static func deletePlainTextCopy() {
        if Prefs.d.object(forKey: Prefs.Key.bttSharedSecret) != nil {
            Prefs.d.removeObject(forKey: Prefs.Key.bttSharedSecret)
            NSLog("SwipeSwitch: deleted a BTT shared secret left in preferences by an earlier version")
        }
    }

    /// Saves a new secret ("" removes it). If the Keychain refuses, the new secret is still used until SwipeSwitch
    /// quits, and Settings says it wasn't saved.
    static func set(_ new: String) {
        lock.lock(); defer { lock.unlock() }
        guard new != cached else { return }
        cached = new
        let status = write(new)
        lastProblem = status == errSecSuccess ? nil
            : "Couldn't save the shared secret to the Keychain (error \(status)). It's used until SwipeSwitch quits, then forgotten."
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Called with `lock` held.
    private static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecSuccess, let data = out as? Data { lastProblem = nil; return String(decoding: data, as: UTF8.self) }
        if status == errSecItemNotFound { lastProblem = nil; return "" }
        NSLog("SwipeSwitch: couldn't read the BTT shared secret from the Keychain (\(status))")
        lastProblem = "Couldn't read the shared secret from the Keychain (error \(status)), so BetterTouchTool commands are sent without it. Turn the option off and on again to retry."
        return ""
    }

    private static func write(_ secret: String) -> OSStatus {
        if secret.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecItemNotFound ? errSecSuccess : status
        }
        let data = Data(secret.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "SwipeSwitch: BetterTouchTool shared secret"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess { NSLog("SwipeSwitch: couldn't save the BTT shared secret to the Keychain (\(status))") }
        return status
    }
}
