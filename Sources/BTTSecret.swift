import Foundation
import Security

/// SwipeSwitch's copy of BetterTouchTool's shared secret (the one typed into Settings › BetterTouchTool), sent with
/// each BTT command. Kept in the login Keychain as SwipeSwitch's own item, not in the preferences file (which any
/// program running as you can read). BTT keeps its own copy in its own Keychain item; this doesn't touch that.
///
/// Read once (the first read after an update may show a Keychain prompt), then served from memory. Thread-safe.
enum BTTSecret {
    private static let service = "io.github.khameedk.swipeswitch.btt-shared-secret"
    private static let account = "BetterTouchTool"
    private static let lock = NSLock()
    private static var cached: String?

    /// The secret, or "" if there is none (or the Keychain wouldn't give it out; then BTT commands go without it,
    /// and BTT turns them down if it requires one). Call off the main thread the first time; see `preload`.
    static var value: String {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        #if SWIPESWITCH_DEV
        // Test runs of a --dev build are a different binary, so the Keychain would ask for your password each time.
        if ProcessInfo.processInfo.environment["SWIPESWITCH_NO_KEYCHAIN"] != nil { cached = ""; return "" }
        #endif
        let v = moveOutOfPreferences() ?? read()
        cached = v
        return v
    }

    /// Reads the secret in the background at launch, so a Keychain prompt never holds up the main thread.
    static func preload() { DispatchQueue.global(qos: .utility).async { _ = value } }

    /// Saves a new secret ("" removes it).
    static func set(_ new: String) {
        lock.lock(); defer { lock.unlock() }
        guard new != cached else { return }
        if write(new) { cached = new }
    }

    /// Earlier versions kept the secret in the preferences file. Moves it into the Keychain and deletes it there; if
    /// the Keychain refuses, keeps using it from preferences so BTT keeps working (and tries again next launch).
    private static func moveOutOfPreferences() -> String? {
        let d = Prefs.d
        guard let old = d.string(forKey: Prefs.Key.bttSharedSecret), !old.isEmpty else { return nil }
        guard write(old) else { return old }
        d.removeObject(forKey: Prefs.Key.bttSharedSecret)
        NSLog("SwipeSwitch: moved the BTT shared secret from preferences into the Keychain")
        return old
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecSuccess, let data = out as? Data { return String(decoding: data, as: UTF8.self) }
        if status != errSecItemNotFound { NSLog("SwipeSwitch: couldn't read the BTT shared secret from the Keychain (\(status))") }
        return ""
    }

    private static func write(_ secret: String) -> Bool {
        if secret.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
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
        return status == errSecSuccess
    }
}
