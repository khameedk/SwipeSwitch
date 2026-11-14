import AppKit
import SwiftUI
import QuartzCore

struct SwitchItem: Identifiable {
    enum Target {
        case app(NSRunningApplication)
        case window(WindowEntry)
    }
    let id: Int
    let title: String
    let icon: NSImage
    let dimmed: Bool
    let target: Target
}

/// Cell geometry shared by the SwiftUI view and the panel sizing code.
struct CellStyle {
    var icon: CGFloat = 64
    var width: CGFloat = 92
    var labelLines = 1

    static let padding: CGFloat = 16
    static let spacing: CGFloat = 6
    static let lineHeight: CGFloat = 14

    var labelHeight: CGFloat { CGFloat(labelLines) * Self.lineHeight }
    var height: CGFloat { icon + 21 + labelHeight }

    static func apps(icon: CGFloat) -> CellStyle { CellStyle(icon: icon, width: icon + 28, labelLines: 1) }
    static func windows(icon: CGFloat) -> CellStyle { CellStyle(icon: icon, width: max(icon + 28, 150), labelLines: 2) }

    func panelSize(count: Int, columns: Int) -> CGSize {
        let cols = max(1, min(columns, count))
        let rows = Int(ceil(Double(count) / Double(cols)))
        return CGSize(width: CGFloat(cols) * width + CGFloat(cols - 1) * Self.spacing + Self.padding * 2,
                      height: CGFloat(rows) * height + CGFloat(rows - 1) * Self.spacing + Self.padding * 2)
    }

    func columnsThatFit(width available: CGFloat) -> Int {
        max(1, Int((available - Self.padding * 2 + Self.spacing) / (width + Self.spacing)))
    }

    func rowsThatFit(height available: CGFloat) -> Int {
        max(1, Int((available - Self.padding * 2 + Self.spacing) / (height + Self.spacing)))
    }
}

final class SwitcherModel: ObservableObject {
    @Published var items: [SwitchItem] = []
    @Published var selected = 0
    @Published var columns = 6
    @Published var style = CellStyle()
    @Published var showAllLabels = false
    @Published var appeared = false
    /// Index of the app/window that's already in front, if it's in the list.
    var currentIndex: Int?
}

struct VisualEffectBackground: NSViewRepresentable {
    var radius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.maskImage = Self.mask(radius)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
    static func mask(_ r: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Namespace private var ns

    private var rows: [[Int]] {
        let c = max(1, model.columns)
        return stride(from: 0, to: model.items.count, by: c).map { Array($0..<min($0 + c, model.items.count)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CellStyle.spacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: CellStyle.spacing) {
                    ForEach(row, id: \.self) { i in cell(i) }
                }
            }
        }
        .padding(CellStyle.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VisualEffectBackground(radius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .scaleEffect(model.appeared ? 1 : 0.96)
        .opacity(model.appeared ? 1 : 0)
    }

    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        let item = model.items[i]
        let isSelected = i == model.selected
        let style = model.style
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: style.icon, height: style.icon)
                .opacity(item.dimmed ? 0.45 : 1)
                .scaleEffect(isSelected ? 1.06 : 1)
            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(style.labelLines)
                .truncationMode(.tail)
                .foregroundStyle(item.dimmed ? .secondary : .primary)
                .frame(width: style.width - 12, height: style.labelHeight, alignment: .top)
                .opacity(isSelected || model.showAllLabels ? 1 : 0)
        }
        .frame(width: style.width, height: style.height)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.13))
                    .matchedGeometryEffect(id: "selection", in: ns)
            }
        }
    }
}

final class SwitcherPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SwitcherController {
    let model = SwitcherModel()
    private let panel = SwitcherPanel()
    private let apps: AppTracker
    private let windows: WindowTracker
    private var generation = 0
    /// Counts switches, so the diagnostic result check can skip one that a newer switch overtook.
    private var switchCount = 0
    /// When the overlay was last shown (diagnostics).
    private var shownAt = 0.0
    private(set) var isShowing = false

    init(apps: AppTracker, windows: WindowTracker) {
        self.apps = apps
        self.windows = windows
        panel.contentView = NSHostingView(rootView: SwitcherView(model: model))
    }

    private func makeItems() -> (items: [SwitchItem], currentIndex: Int?) {
        let wins = windows.candidates()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let byName = Prefs.sort == .name
        func less(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }

        switch Prefs.mode {
        case .apps:
            var (list, _) = apps.candidates(owners: Dictionary(wins.map { ($0.app.processIdentifier, $0.app) }, uniquingKeysWith: { a, _ in a }))
            if byName { list.sort { less($0.localizedName ?? "", $1.localizedName ?? "") } }
            let items = list.enumerated().map { i, app in
                SwitchItem(id: i, title: app.localizedName ?? "App", icon: app.icon ?? NSImage(),
                           dimmed: !wins.contains { $0.app.processIdentifier == app.processIdentifier && !$0.dimmed },
                           target: .app(app))
            }
            return (items, list.firstIndex { $0.processIdentifier == frontPID })
        case .windows:
            // The most recently focused window is the current one if its app is in front.
            let currentID = wins.first.flatMap { $0.app.processIdentifier == frontPID ? $0.id : nil }
            var list = Array(wins.prefix(Prefs.maxApps))
            if byName {
                list.sort { a, b in
                    let an = a.app.localizedName ?? "", bn = b.app.localizedName ?? ""
                    return an == bn ? less(a.title, b.title) : less(an, bn)
                }
            }
            let items = list.enumerated().map { i, w in
                let appName = w.app.localizedName ?? "App"
                return SwitchItem(id: i, title: w.title.isEmpty ? appName : w.title, icon: w.app.icon ?? NSImage(),
                                  dimmed: w.dimmed, target: .window(w))
            }
            return (items, list.firstIndex { $0.id == currentID })
        }
    }

    /// Opens the switcher with the previous app/window selected. Returns false if there's nothing to switch to.
    /// A list built ahead of time (when fingers touch down or ⌘ is pressed), used if it's still fresh.
    private var prepared: (items: [SwitchItem], currentIndex: Int?, at: Double)?
    private static let preparedMaxAge = 1.0

    /// Builds the list ahead of time so opening is instant. Cheap to call often; skips if recently built.
    func prepare() {
        guard !isShowing else { return }
        if let p = prepared, CACurrentMediaTime() - p.at < 0.3 { return }
        let (items, currentIndex) = SessionLog.timed("building the list at touch-down") { makeItems() }
        prepared = (items, currentIndex, CACurrentMediaTime())
    }

    /// One-time warm-up at launch: builds a list and renders the overlay off-screen, so the first real open
    /// isn't slower than the rest.
    func warmUp() {
        let (items, _) = makeItems()
        guard !isShowing, !items.isEmpty else { return }
        model.items = Array(items.prefix(2))
        model.style = CellStyle.apps(icon: CGFloat(Prefs.iconSize))
        model.columns = 2
        let size = model.style.panelSize(count: model.items.count, columns: 2)
        panel.setFrame(NSRect(origin: .zero, size: size), display: false)
        if let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.layoutSubtreeIfNeeded()
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        model.items = []
    }

    /// Haptics only make sense for trackpad sessions (you feel them through the trackpad).
    private var sessionHaptics = true

    /// - Parameters:
    ///   - startAtEnd: select the last item (⌘⇧Tab) instead of the one after the current app/window.
    ///   - haptics: whether to click the trackpad on each step.
    func begin(startAtEnd: Bool = false, haptics: Bool = true) -> Bool {
        sessionHaptics = haptics
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return false }

        var (items, currentIndex): ([SwitchItem], Int?)
        if let p = prepared, CACurrentMediaTime() - p.at < Self.preparedMaxAge {
            (items, currentIndex) = (p.items, p.currentIndex)
        } else {
            (items, currentIndex) = SessionLog.timed("building the list on open") { makeItems() }
        }
        prepared = nil
        guard items.count >= (currentIndex == nil ? 1 : 2) else { return false }

        let windowsMode = Prefs.mode == .windows
        let icon = CGFloat(windowsMode ? min(Prefs.iconSize, 72) : Prefs.iconSize)
        var style = windowsMode ? CellStyle.windows(icon: icon) : CellStyle.apps(icon: icon)
        let maxW = vis.width * 0.92
        var cols: Int
        if Prefs.layout == .grid {
            cols = min(Prefs.columns, items.count, style.columnsThatFit(width: maxW))
        } else {
            cols = items.count
            if cols > style.columnsThatFit(width: maxW) {
                if windowsMode {
                    cols = style.columnsThatFit(width: maxW)   // titles need their width: wrap instead of shrinking
                } else {
                    let perCell = (maxW - CellStyle.padding * 2) / CGFloat(cols) - CellStyle.spacing
                    style = CellStyle.apps(icon: max(24, floor(perCell - 28)))
                }
            }
        }
        items = Array(items.prefix(style.rowsThatFit(height: vis.height * 0.9) * cols))

        model.items = items
        model.columns = cols
        model.style = style
        model.showAllLabels = windowsMode || Prefs.showAllNames
        if let c = currentIndex, c >= items.count { currentIndex = nil }   // trimmed off the end
        model.currentIndex = currentIndex
        // Start on the item after the current one (the previous app/window when sorted by last active).
        model.selected = startAtEnd ? items.count - 1 : (currentIndex.map { ($0 + 1) % items.count } ?? 0)
        model.appeared = false

        let size = style.panelSize(count: items.count, columns: cols)
        panel.setFrame(NSRect(x: (vis.midX - size.width / 2).rounded(),
                              y: (vis.midY - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: false)

        generation += 1
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) { self.model.appeared = true }
        }
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if gen == self.generation { self.panel.invalidateShadow() } }
        isShowing = true
        shownAt = CACurrentMediaTime()
        SessionLog.note("opened via \(haptics ? "swipe" : "keys") mode=\(Prefs.mode.rawValue) items=\(items.count) current=\(currentIndex ?? -1) selected=\(self.model.selected)")
        BetterTouchTool.setActive(true)
        haptic()
        return true
    }

    func step(dx: Int, dy: Int) {
        guard isShowing else { return }
        let n = model.items.count
        guard n > 0 else { return }
        var i = model.selected + dx + dy * model.columns
        if Prefs.wrapAround {
            i = ((i % n) + n) % n
        } else {
            i = min(max(i, 0), n - 1)
        }
        guard i != model.selected else { return }
        SessionLog.note("step (\(dx),\(dy)) -> selected=\(i)")
        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { model.selected = i }
        haptic()
    }

    func commit() {
        guard isShowing else { return }
        let index = model.selected
        let target = model.items.indices.contains(index) ? model.items[index].target : nil
        let switching = target != nil && index != model.currentIndex
        hide(switching: switching)
        guard let target, switching else {
            SessionLog.note("commit: selected=\(index) is already in front, nothing to switch")
            return
        }
        let targetApp: NSRunningApplication
        var targetWindow: CGWindowID?
        switch target {
        case .app(let app):
            targetApp = app
            SessionLog.timed("activating \(app.localizedName ?? "?")") { Activator.activate(app) }
        case .window(let w):
            targetApp = w.app
            targetWindow = w.id
            windows.noteActivated(w.id)
            SessionLog.timed("activating a \(w.app.localizedName ?? "?") window") { Activator.activate(window: w) }
        }
        let name = targetApp.localizedName ?? "?"
        SessionLog.note("commit: switching to \(name) (selected=\(index))")
        // With diagnostics on, check that the switch actually landed (after the safety net has had its chance).
        guard SessionLog.enabled else { return }
        switchCount += 1
        let thisSwitch = switchCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard thisSwitch == self.switchCount else { return }   // a newer switch followed; it gets its own check
            let front = NSWorkspace.shared.frontmostApplication
            Activator.axQueue.async { Self.logResult(name: name, target: targetApp, window: targetWindow, front: front) }
        }
    }

    /// Diagnostics, on `Activator.axQueue` (it asks the app which window is focused).
    private static func logResult(name: String, target targetApp: NSRunningApplication, window targetWindow: CGWindowID?,
                                  front: NSRunningApplication?) {
        let appOK = front?.processIdentifier == targetApp.processIdentifier
        var windowNote = ""
        if let wid = targetWindow, appOK {
            var focused: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(targetApp.processIdentifier), kAXFocusedWindowAttribute as CFString, &focused)
            let fid = focused.flatMap { PrivateAPI.windowID(of: $0 as! AXUIElement) }
            windowNote = fid == wid ? ", right window focused" : ", but a different window is focused"
        }
        if appOK {
            SessionLog.note("result: switch to \(name) CONFIRMED\(windowNote)")
        } else {
            SessionLog.problem("result: switch to \(name) FAILED, front is \(front?.localizedName ?? "?")")
        }
    }

    func cancel() {
        if isShowing { SessionLog.note("cancelled") }
        guard isShowing else { return }
        hide()
    }

    /// `switching`: an app is being brought to the front. Opening BTT's link at that same moment can make macOS hand the
    /// front back to the previous app for a moment (the window visibly flickers), so the link waits until the switch
    /// has settled. BTT gestures stay paused that half second longer, which does no harm.
    private func hide(switching: Bool = false) {
        let shownFor = Int((CACurrentMediaTime() - shownAt) * 1000)
        SessionLog.note("overlay closed after \(shownFor) ms\(shownFor < 100 ? " (likely too quick to see)" : "")")
        isShowing = false
        generation += 1
        let gen = generation
        if switching {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if gen == self.generation { BetterTouchTool.setActive(false) }   // unless the switcher reopened
            }
        } else {
            BetterTouchTool.setActive(false)
        }
        withAnimation(.easeOut(duration: 0.12)) { model.appeared = false }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            if gen == self.generation { self.panel.orderOut(nil) }
        })
    }

    /// Renders the overlay's current contents to a PNG (used by demo mode for visual checks).
    func snapshot(to path: String) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func haptic() {
        guard Prefs.haptics, sessionHaptics else { return }
        if !MultitouchMonitor.shared.haptic(strength: Prefs.hapticStrength.actuationID) {
            NSLog("SwipeSwitch: trackpad haptics unavailable, using system haptics")
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
