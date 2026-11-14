import AppKit

/// macOS's own ⌘Tab / ⌘⇧Tab app switcher shortcuts ("symbolic hot keys"), switched via a private call
/// that other app switchers use too.
enum SystemCommandTab {
    private typealias SetFn = @convention(c) (Int32, Bool) -> Int32
    private typealias IsFn = @convention(c) (Int32) -> Bool
    private static let handle = dlopen(nil, RTLD_NOW)
    private static let setEnabled = dlsym(handle, "CGSSetSymbolicHotKeyEnabled").map { unsafeBitCast($0, to: SetFn.self) }
    private static let isEnabled = dlsym(handle, "CGSIsSymbolicHotKeyEnabled").map { unsafeBitCast($0, to: IsFn.self) }
    private static let hotKeys: [Int32] = [1, 2]   // ⌘Tab, ⌘⇧Tab

    /// nil if unknown.
    static var enabled: Bool? { isEnabled.map { fn in hotKeys.allSatisfy { fn($0) } } }

    static func set(_ on: Bool) {
        guard let setEnabled else { return }
        for key in hotKeys { _ = setEnabled(key, on) }
    }
}

/// Optional ⌘Tab support. Watches the keyboard with an event tap (needs Accessibility) and drives the switcher:
/// ⌘Tab opens it; while ⌘ is held, Tab moves forward, Shift (or ⇧Tab) moves back, arrow keys move around;
/// releasing ⌘ switches, Esc cancels.
/// Every other key passes through untouched.
final class KeyboardSwitcher {
    var onOpen: ((_ startAtEnd: Bool) -> Bool)?
    /// ⌘ was just pressed (⌘Tab may follow): a chance to prepare ahead of time. Called asynchronously,
    /// after the key event has been passed on, so ordinary ⌘ shortcuts are never delayed.
    var onCommandDown: (() -> Void)?
    private var commandWasDown = false
    var onStep: ((Int, Int) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Returns true while a trackpad gesture owns the switcher.
    var isGestureActive: (() -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// True while the switcher is open because of ⌘Tab.
    private(set) var isActive = false
    /// Shift state from the last modifier change, so a Shift *press* can be told apart from Shift being held.
    private var shiftWasDown = false

    var isRunning: Bool { tap != nil }

    /// Starts or stops listening to match the setting.
    func apply() {
        if Prefs.keyboardTrigger { start() } else { stop() }
    }

    private func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: keyTapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("SwipeSwitch: keyboard listener unavailable (needs Accessibility access)")
            return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        NSLog("SwipeSwitch: ⌘Tab listener on (macOS ⌘Tab was \(SystemCommandTab.enabled == true ? "on" : "already off"))")

        // Take ⌘Tab from macOS, remembering that we did so we only ever restore our own change.
        if SystemCommandTab.enabled == true {
            SystemCommandTab.set(false)
            Prefs.d.set(true, forKey: Prefs.Key.disabledSystemCommandTab)
        }
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        if isActive { isActive = false; onCancel?() }
        Self.restoreSystemCommandTabIfWeChangedIt()
    }

    /// Also called at launch, in case a previous run quit without restoring it.
    static func restoreSystemCommandTabIfWeChangedIt() {
        guard Prefs.d.bool(forKey: Prefs.Key.disabledSystemCommandTab) else { return }
        SystemCommandTab.set(true)
        Prefs.d.removeObject(forKey: Prefs.Key.disabledSystemCommandTab)
    }

    private enum Key {
        static let tab: Int64 = 48, escape: Int64 = 53, returnKey: Int64 = 36, enter: Int64 = 76
        static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    }

    /// Returns nil to swallow the event, or the event to let it through.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        let flags = event.flags
        let command = flags.contains(.maskCommand)

        switch type {
        case .flagsChanged:
            let shift = flags.contains(.maskShift)
            defer { shiftWasDown = shift; commandWasDown = command }
            if !isActive && command && !commandWasDown, let prep = onCommandDown {
                DispatchQueue.main.async { prep() }
            }
            if isActive && !command {          // ⌘ released: switch
                isActive = false
                onCommit?()
            } else if isActive && shift && !shiftWasDown {
                onStep?(-1, 0)                 // pressing Shift (with ⌘ held) moves back one
            }
            return pass

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let shift = flags.contains(.maskShift)
            if !isActive {
                let otherModifiers = flags.contains(.maskControl) || flags.contains(.maskAlternate)
                guard code == Key.tab, command, !otherModifiers, isGestureActive?() != true else { return pass }
                isActive = onOpen?(shift) == true
                return nil
            }
            switch code {
            case Key.tab: onStep?(shift ? -1 : 1, 0)
            case Key.left: onStep?(-1, 0)
            case Key.right: onStep?(1, 0)
            case Key.down: onStep?(0, 1)
            case Key.up: onStep?(0, -1)
            case Key.escape:
                isActive = false
                onCancel?()
            case Key.returnKey, Key.enter:
                isActive = false
                onCommit?()
            default: break                     // other ⌘-keys are ignored while the switcher is open
            }
            return nil

        case .keyUp:
            return isActive ? nil : pass

        default:
            return pass
        }
    }

    #if SWIPESWITCH_DEV
    /// Feeds a key event straight to the handler (used by demo mode; nothing is posted to the system).
    func simulate(type: CGEventType, keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type != .keyUp) else { return }
        if type == .flagsChanged { event.type = .flagsChanged }
        event.flags = flags
        _ = handle(type: type, event: event)
    }
    #endif
}

private let keyTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardSwitcher>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}

/// While a switcher opened by a trackpad swipe is on screen, catches Esc (and only Esc) so it can cancel.
/// It listens only for as long as the switcher is open; every other key passes straight through.
final class EscapeWatcher {
    var onEscape: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        guard tap == nil else { return }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                        callback: escapeTapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [weak self] in self?.onEscape?() }
        return nil   // Esc was for the switcher, so the app in front doesn't also get it
    }

    #if SWIPESWITCH_DEV
    /// Used by demo mode (nothing is sent to the system).
    func simulateEscape() { onEscape?() }
    #endif
}

private let escapeTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EscapeWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
