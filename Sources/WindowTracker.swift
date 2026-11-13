import AppKit
import ApplicationServices

/// Private window-server / accessibility calls (looked up at runtime; everything degrades gracefully without them).
enum PrivateAPI {
    private typealias GetWindowFn = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias RemoteTokenFn = @convention(c) (UnsafeRawPointer) -> UnsafeMutableRawPointer?
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, UnsafeRawPointer) -> UnsafeMutableRawPointer?

    private static let handle = dlopen(nil, RTLD_NOW)
    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    private static let getWindow = sym("_AXUIElementGetWindow", GetWindowFn.self)
    private static let remoteToken = sym("_AXUIElementCreateWithRemoteToken", RemoteTokenFn.self)
    private static let mainConnection = sym("CGSMainConnectionID", MainConnectionFn.self)
    private static let spacesForWindows = sym("CGSCopySpacesForWindows", SpacesForWindowsFn.self)

    /// The CGWindowID behind an accessibility window element.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        let ok = getWindow(Unmanaged.passUnretained(element).toOpaque(), &id) == .success
        return ok && id != 0 ? id : nil
    }

    /// Number of desktops (Spaces) a window lives on, or nil if unknown. Invisible helper windows live on none.
    static func spaceCount(for id: CGWindowID) -> Int? {
        guard let mainConnection, let spacesForWindows else { return nil }
        let ids = [NSNumber(value: id)] as CFArray
        guard let raw = spacesForWindows(mainConnection(), 7, Unmanaged.passUnretained(ids).toOpaque()) else { return 0 }
        let spaces = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        return CFArrayGetCount(spaces)
    }

    private typealias ManagedSpacesFn = @convention(c) (Int32) -> UnsafeMutableRawPointer?
    private typealias WindowsOnSpacesFn = @convention(c) (Int32, Int32, UnsafeRawPointer, Int32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> UnsafeMutableRawPointer?
    private static let managedSpaces = sym("CGSCopyManagedDisplaySpaces", ManagedSpacesFn.self)
    private static let windowsOnSpaces = sym("CGSCopyWindowsWithOptionsAndTags", WindowsOnSpacesFn.self)

    /// IDs of windows actually shown on some desktop (current or not). Closed-but-kept windows,
    /// minimized windows and hidden apps' windows are not included. Nil if unavailable.
    static func visibleWindowIDsOnAllDesktops() -> Set<CGWindowID>? {
        guard let mainConnection, let managedSpaces, let windowsOnSpaces,
              let raw = managedSpaces(mainConnection()) else { return nil }
        let cid = mainConnection()
        guard let displays = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue() as? [[String: Any]] else { return nil }
        var ids = Set<CGWindowID>()
        for display in displays {
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let sid = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
                var setTags: UInt64 = 0, clearTags: UInt64 = 0
                let arr = [NSNumber(value: sid)] as CFArray
                guard let list = windowsOnSpaces(cid, 0, Unmanaged.passUnretained(arr).toOpaque(), 2, &setTags, &clearTags) else { continue }
                for n in Unmanaged<CFArray>.fromOpaque(list).takeRetainedValue() as? [NSNumber] ?? [] { ids.insert(n.uint32Value) }
            }
        }
        return ids
    }

    /// Accessibility only lists windows on the current desktop. To reach a window on another desktop,
    /// probe the app's element IDs directly (the same technique other window switchers use).
    static func windowElementOnAnyDesktop(pid: pid_t, id target: CGWindowID) -> AXUIElement? {
        guard let remoteToken else { return nil }
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            buf.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            buf.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        let deadline = CACurrentMediaTime() + 0.35
        for elementID: UInt64 in 0..<2000 {
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            let cfData = token as CFData
            guard let raw = remoteToken(Unmanaged.passUnretained(cfData).toOpaque()) else { continue }
            let el = Unmanaged<AXUIElement>.fromOpaque(raw).takeRetainedValue()
            if windowID(of: el) == target { return el }
            if CACurrentMediaTime() > deadline { break }
        }
        return nil
    }
}

struct WindowEntry {
    let id: CGWindowID
    let app: NSRunningApplication
    let title: String
    let minimized: Bool
    let hidden: Bool      // its app is hidden (Cmd-H)
    var dimmed: Bool { minimized || hidden }
}

/// Lists individual windows (across desktops) in most-recently-focused order, with their titles.
final class WindowTracker {
    private var stamps: [CGWindowID: Double] = [:]
    private var titles: [CGWindowID: String] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private let myPID = ProcessInfo.processInfo.processIdentifier

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.ensureObserver(for: app)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.stampFocusedWindow(of: app.processIdentifier) }
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.ensureObserver(for: app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let obs = self?.observers.removeValue(forKey: app.processIdentifier) else { return }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        ensureObservers()
    }

    // MARK: Focus tracking

    func ensureObservers() {
        guard AXIsProcessTrusted() else { return }
        for app in NSWorkspace.shared.runningApplications { ensureObserver(for: app) }
    }

    private func ensureObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard AXIsProcessTrusted(), app.activationPolicy == .regular, pid != myPID, observers[pid] == nil else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, windowFocusCallback, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var added = false
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            if AXObserverAddNotification(obs, el, name as CFString, refcon) == .success { added = true }
        }
        guard added else { return }   // app not ready yet; we'll retry later
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    fileprivate func noteFocused(_ window: AXUIElement) {
        guard let id = PrivateAPI.windowID(of: window) else { return }
        stamps[id] = CACurrentMediaTime()
        if let t = Self.string(window, kAXTitleAttribute), !t.isEmpty { titles[id] = t }
    }

    func noteActivated(_ id: CGWindowID) { stamps[id] = CACurrentMediaTime() }

    private func stampFocusedWindow(of pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let el = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &win) == .success, let win {
            noteFocused(win as! AXUIElement)
        }
    }

    // MARK: Listing

    private struct AXInfo { let element: AXUIElement; let title: String; let minimized: Bool }

    /// Windows on the current desktop as Accessibility sees them (nil if unavailable).
    private func axWindows(pid: pid_t) -> [CGWindowID: AXInfo]? {
        let el = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return nil }
        var out: [CGWindowID: AXInfo] = [:]
        for w in list {
            guard let id = PrivateAPI.windowID(of: w) else { continue }
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized)
            out[id] = AXInfo(element: w, title: Self.string(w, kAXTitleAttribute) ?? "", minimized: (minimized as? Bool) ?? false)
        }
        return out
    }

    /// Real windows the user could switch to, honoring scope, the minimized/hidden options and exclusions,
    /// most recently focused first.
    func candidates() -> [WindowEntry] {
        let trusted = AXIsProcessTrusted()
        if trusted { ensureObservers() }
        if let front = NSWorkspace.shared.frontmostApplication { stampFocusedWindow(of: front.processIdentifier) }

        let scope = Prefs.scope
        let includeMinimized = Prefs.includeMinimized
        let includeHidden = Prefs.includeHidden
        let excluded = Set(Prefs.excluded)
        var apps: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != myPID && !excluded.contains(app.bundleIdentifier ?? "") {
            apps[app.processIdentifier] = app
        }

        let onScreen = Set(Self.windowIDs(onScreenOnly: true))
        let visibleAnywhere = PrivateAPI.visibleWindowIDsOnAllDesktops()
        guard let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }

        var axCache: [pid_t: [CGWindowID: AXInfo]?] = [:]
        var found: [(entry: WindowEntry, rank: Int)] = []
        for (rank, w) in all.enumerated() {
            guard (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = apps[pid],
                  let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if let b = w[kCGWindowBounds as String] as? [String: Any],
               let width = (b["Width"] as? NSNumber)?.doubleValue,
               let height = (b["Height"] as? NSNumber)?.doubleValue,
               width < 80 || height < 40 { continue }
            if let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 { continue }

            if trusted && axCache[pid] == nil { axCache[pid] = axWindows(pid: pid) }
            let ax: [CGWindowID: AXInfo]? = trusted ? (axCache[pid] ?? nil) : nil
            let info = ax?[id]
            var minimized = false
            var hidden = false

            if onScreen.contains(id) {
                // Drawn on this desktop. If Accessibility knows the app's windows, use it to weed out overlays.
                if let ax, !ax.isEmpty, info == nil { continue }
            } else if visibleAnywhere?.contains(id) == true {
                // Shown on another desktop.
                if scope == .current { continue }
            } else if let info, info.minimized {
                minimized = true
            } else if app.isHidden, info != nil || (PrivateAPI.spaceCount(for: id) ?? 0) > 0 {
                // Windows of a hidden app aren't drawn anywhere, but still belong to a desktop.
                if scope == .current && info == nil { continue }
                hidden = true
            } else if visibleAnywhere == nil {
                // Window-server lookup unavailable: fall back to "belongs to some desktop".
                if scope == .current { continue }
                if (PrivateAPI.spaceCount(for: id) ?? (titles[id] != nil ? 1 : 0)) == 0 { continue }
            } else {
                continue   // closed window the app keeps around, or an invisible helper window
            }
            if minimized && !includeMinimized { continue }
            if hidden && !includeHidden { continue }

            var title = (w[kCGWindowName as String] as? String) ?? ""
            if title.isEmpty { title = info?.title ?? "" }
            if title.isEmpty { title = titles[id] ?? "" }
            if !title.isEmpty { titles[id] = title }

            found.append((WindowEntry(id: id, app: app, title: title, minimized: minimized, hidden: hidden), rank))
        }

        found.sort { a, b in
            switch (stamps[a.entry.id], stamps[b.entry.id]) {
            case let (sa?, sb?): return sa > sb
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.rank < b.rank
            }
        }
        return found.map(\.entry)
    }

    private static func windowIDs(onScreenOnly: Bool) -> [CGWindowID] {
        let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }
}

private let windowFocusCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue().noteFocused(element)
}
