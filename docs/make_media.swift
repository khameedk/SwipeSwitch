// Draws the README's example images: a mock desktop with macOS's built-in app icons (Safari, Mail, …, read
// from the system, identical on every Mac). Window contents are made up; nothing is captured from a real screen.
// App icons and the Apple logo are Apple's trademarks and artwork.
// Usage (from the repo root): swift docs/make_media.swift docs/images
// Each image is saved under a name containing a fingerprint of its contents (e.g. swipeswitch-demo-1a2b3c4d.gif),
// the previous version is removed, and README.md's links are updated, so browsers never show a stale cached copy.
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images"
let readmePath = "README.md"

/// Renames a freshly written `<name>.<ext>` to `<name>-<fingerprint>.<ext>`, deletes older versions, and points
/// README.md's links at the new file.
func publish(_ name: String, _ ext: String) {
    let fm = FileManager.default
    let tmp = "\(outDir)/\(name).\(ext)"
    guard let data = fm.contents(atPath: tmp) else { return }
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(8)
    let final = "\(name)-\(hash).\(ext)"
    for old in (try? fm.contentsOfDirectory(atPath: outDir)) ?? []
    where old != final && old.hasPrefix("\(name)-") && old.hasSuffix(".\(ext)") {
        try? fm.removeItem(atPath: "\(outDir)/\(old)")
    }
    try? fm.removeItem(atPath: "\(outDir)/\(final)")
    try? fm.moveItem(atPath: tmp, toPath: "\(outDir)/\(final)")
    if var readme = try? String(contentsOfFile: readmePath, encoding: .utf8) {
        let pattern = "\(NSRegularExpression.escapedPattern(for: outDir))/\(name)(-[0-9a-f]{8})?\\.\(ext)"
        let regex = try! NSRegularExpression(pattern: pattern)
        readme = regex.stringByReplacingMatches(in: readme, range: NSRange(readme.startIndex..., in: readme),
                                                withTemplate: "\(outDir)/\(final)")
        try? readme.write(toFile: readmePath, atomically: true, encoding: .utf8)
    }
    print("\(outDir)/\(final)")
}
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - Mock apps

struct MockApp {
    let name: String; let symbol: String; let top: NSColor; let bottom: NSColor; var glyph: NSColor = .white
    var path: String? = nil
    /// The real app icon from the system, if this Mac has the app; otherwise a drawn stand-in is used.
    var icon: NSImage? {
        // Resolve links first (Safari's /Applications entry is one), or macOS adds a shortcut-arrow badge.
        guard let p = path.map({ ($0 as NSString).resolvingSymlinksInPath }), FileManager.default.fileExists(atPath: p) else { return nil }
        return NSWorkspace.shared.icon(forFile: p)
    }
}
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let browser = MockApp(name: "Safari", symbol: "safari", top: rgb(80, 150, 250), bottom: rgb(30, 95, 215), path: "/Applications/Safari.app")
let mail = MockApp(name: "Mail", symbol: "envelope.fill", top: rgb(70, 185, 255), bottom: rgb(15, 115, 235), path: "/System/Applications/Mail.app")
let notes = MockApp(name: "Notes", symbol: "note.text", top: rgb(255, 222, 95), bottom: rgb(245, 175, 35), path: "/System/Applications/Notes.app")
let photos = MockApp(name: "Photos", symbol: "photo.fill", top: rgb(255, 135, 160), bottom: rgb(225, 65, 125), path: "/System/Applications/Photos.app")
let music = MockApp(name: "Music", symbol: "music.note", top: rgb(255, 100, 110), bottom: rgb(215, 45, 75), path: "/System/Applications/Music.app")
let terminal = MockApp(name: "Terminal", symbol: "terminal.fill", top: rgb(85, 85, 95), bottom: rgb(35, 35, 42), path: "/System/Applications/Utilities/Terminal.app")
let calendar = MockApp(name: "Calendar", symbol: "calendar", top: rgb(255, 255, 255), bottom: rgb(220, 220, 226), glyph: rgb(230, 60, 60), path: "/System/Applications/Calendar.app")
let chat = MockApp(name: "Messages", symbol: "message.fill", top: rgb(95, 220, 130), bottom: rgb(35, 165, 85), path: "/System/Applications/Messages.app")
let files = MockApp(name: "Finder", symbol: "folder.fill", top: rgb(120, 200, 255), bottom: rgb(65, 145, 235), path: "/System/Library/CoreServices/Finder.app")
let maps = MockApp(name: "Maps", symbol: "map.fill", top: rgb(130, 210, 150), bottom: rgb(65, 155, 105), path: "/System/Applications/Maps.app")
let allApps = [browser, mail, notes, photos, music, terminal, calendar, chat, files, maps]

// MARK: - Drawing helpers

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

func drawIcon(_ app: MockApp, in r: NSRect) {
    if let img = app.icon {
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        return
    }
    let path = rounded(r, r.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowBlurRadius = r.width * 0.06; sh.shadowOffset = NSSize(width: 0, height: -r.width * 0.03)
    sh.shadowColor = NSColor.black.withAlphaComponent(0.25); sh.set()
    app.bottom.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: app.top, ending: app.bottom)!.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: r.width * 0.44, weight: .semibold).applying(.init(paletteColors: [app.glyph]))
    if let sym = NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let s = sym.size
        sym.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height))
    }
}

func text(_ s: String, in r: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor,
          align: NSTextAlignment = .left, lines: Int = 1) {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p])
        .draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 8, _ c: NSColor = rgb(0, 0, 0, 0.10)) {
    c.setFill(); rounded(NSRect(x: x, y: y, width: w, height: h), h / 2).fill()
}

func render(_ size: NSSize, _ draw: () -> Void) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}
var scale: CGFloat = 1

let ciContext = CIContext()
func blurred(_ image: CGImage, radius: CGFloat) -> CGImage {
    let ci = CIImage(cgImage: image)
    let out = ci.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: ci.extent)
    return ciContext.createCGImage(out, from: ci.extent)!
}

// MARK: - Mock desktop

enum Front { case browser, notes }

func drawDesktop(_ canvas: NSSize, front: Front) {
    drawWallpaper(canvas)
    // Menu bar: translucent, Apple logo, bold app name, menus, status icons and the clock.
    let mb = NSRect(x: 0, y: canvas.height - 25, width: canvas.width, height: 25)
    rgb(255, 255, 255, 0.45).setFill(); mb.fill()
    let ink = rgb(15, 15, 20)
    func symbol(_ name: String, x: CGFloat, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> CGFloat {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [ink]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return 0 }
        img.draw(in: NSRect(x: x, y: mb.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        return img.size.width
    }
    _ = symbol("apple.logo", x: 16, size: 14, weight: .medium)
    let appName = front == .browser ? "Safari" : "Notes"
    let font = NSFont.systemFont(ofSize: 13)
    var x: CGFloat = 46
    for (i, item) in ([appName] + ["File", "Edit", "View", front == .browser ? "History" : "Format", "Window", "Help"]).enumerated() {
        let f = i == 0 ? NSFont.systemFont(ofSize: 13, weight: .bold) : font
        let w = (item as NSString).size(withAttributes: [.font: f]).width
        NSAttributedString(string: item, attributes: [.font: f, .foregroundColor: ink]).draw(at: NSPoint(x: x, y: mb.minY + 5))
        x += w + 20
    }
    let clock = "Fri Nov 13  10:12"
    let cw = (clock as NSString).size(withAttributes: [.font: font]).width
    var rx = canvas.width - 14 - cw
    NSAttributedString(string: clock, attributes: [.font: font, .foregroundColor: ink]).draw(at: NSPoint(x: rx, y: mb.minY + 5))
    for name in ["switch.2", "magnifyingglass", "wifi", "battery.75percent"] {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let w = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)?.size.width ?? 16
        rx -= w + 16
        _ = symbol(name, x: rx)
    }

    // Back window (the other app), slightly offset
    func window(_ r: NSRect, title: String, body: (NSRect) -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowBlurRadius = 22; sh.shadowOffset = NSSize(width: 0, height: -8)
        sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.set()
        NSColor.white.setFill(); rounded(r, 11).fill()
        NSGraphicsContext.restoreGraphicsState()
        let titleBar = NSRect(x: r.minX, y: r.maxY - 38, width: r.width, height: 38)
        rgb(246, 246, 248).setFill(); NSBezierPath(roundedRect: titleBar, xRadius: 11, yRadius: 11).fill()
        rgb(246, 246, 248).setFill(); NSRect(x: titleBar.minX, y: titleBar.minY, width: titleBar.width, height: 12).fill()
        rgb(0, 0, 0, 0.08).setFill(); NSRect(x: r.minX, y: titleBar.minY, width: r.width, height: 1).fill()
        for (i, c) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: r.minX + 14 + CGFloat(i) * 20, y: titleBar.midY - 6, width: 12, height: 12)).fill()
        }
        text(title, in: NSRect(x: r.minX + 80, y: titleBar.midY - 8, width: r.width - 160, height: 16), size: 12.5, weight: .semibold,
             color: rgb(60, 60, 66), align: .center)
        NSGraphicsContext.saveGraphicsState()
        rounded(r, 11).addClip()   // keep page content inside the window
        body(NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 38))
        NSGraphicsContext.restoreGraphicsState()
    }

    let browserWin = { (r: NSRect) in
        window(r, title: "Weekend recipes") { b in
            rgb(240, 240, 244).setFill(); rounded(NSRect(x: b.minX + 120, y: b.maxY - 32, width: b.width - 240, height: 22), 11).fill()
            text("example.com/recipes", in: NSRect(x: b.minX + 120, y: b.maxY - 29, width: b.width - 240, height: 16), size: 11.5,
                 color: rgb(100, 100, 110), align: .center)
            text("Weekend recipes", in: NSRect(x: b.minX + 40, y: b.maxY - 82, width: 400, height: 30), size: 24, weight: .bold, color: rgb(25, 25, 30))
            NSGradient(starting: rgb(255, 190, 120), ending: rgb(230, 110, 90))!.draw(in: rounded(NSRect(x: b.minX + 40, y: b.maxY - 250, width: 240, height: 150), 10), angle: -60)
            for (i, w) in [300.0, 280, 310, 260, 290, 200].enumerated() { bar(b.minX + 300, b.maxY - 112 - CGFloat(i) * 22, CGFloat(w)) }
            for (i, w) in [560.0, 520, 540, 380].enumerated() { bar(b.minX + 40, b.maxY - 280 - CGFloat(i) * 22, CGFloat(w)) }
        }
    }
    let notesWin = { (r: NSRect) in
        window(r, title: "Project ideas") { b in
            rgb(250, 248, 240).setFill(); NSRect(x: b.minX, y: b.minY, width: 170, height: b.height).fill()
            for (i, w) in [110.0, 90, 120, 80, 100].enumerated() {
                bar(b.minX + 18, b.maxY - 32 - CGFloat(i) * 40, CGFloat(w), 9, i == 0 ? rgb(245, 175, 35, 0.9) : rgb(0, 0, 0, 0.10))
                bar(b.minX + 18, b.maxY - 47 - CGFloat(i) * 40, CGFloat(w) * 0.6, 6, rgb(0, 0, 0, 0.06))
            }
            text("Project ideas", in: NSRect(x: b.minX + 200, y: b.maxY - 52, width: 400, height: 30), size: 22, weight: .bold, color: rgb(25, 25, 30))
            for (i, w) in [380.0, 350, 400, 300, 360, 330, 240, 370, 280].enumerated() { bar(b.minX + 200, b.maxY - 84 - CGFloat(i) * 22, CGFloat(w)) }
        }
    }
    let main = NSRect(x: 70, y: 96, width: canvas.width - 140, height: canvas.height - 150)
    let back = main.offsetBy(dx: 26, dy: -16)
    if front == .browser { notesWin(back); browserWin(main) } else { browserWin(back); notesWin(main) }

    // Dock: Finder first, frosted glass, a divider before the Trash, dots under running apps.
    let dockApps = [files, browser, mail, chat, maps, photos, calendar, notes, music, terminal]
    let running: Set<String> = ["Finder", "Safari", "Mail", "Messages", "Notes", "Music", "Terminal"]
    let icon: CGFloat = 44, gap: CGFloat = 5, divider: CGFloat = 13
    let dockW = CGFloat(dockApps.count + 1) * (icon + gap) + gap + divider
    let dock = NSRect(x: (canvas.width - dockW) / 2, y: 6, width: dockW, height: icon + 14)
    NSGraphicsContext.saveGraphicsState()
    let dshape = rounded(dock, 18)
    dshape.addClip()
    if let blur = wallpaperBlur { NSGraphicsContext.current!.cgContext.draw(blur, in: CGRect(origin: .zero, size: canvas)) }
    rgb(255, 255, 255, 0.30).setFill(); dshape.fill()
    NSGraphicsContext.restoreGraphicsState()
    rgb(255, 255, 255, 0.45).setStroke(); let db = rounded(dock.insetBy(dx: 0.5, dy: 0.5), 18); db.lineWidth = 1; db.stroke()
    var dx = dock.minX + gap
    for a in dockApps {
        drawIcon(a, in: NSRect(x: dx, y: dock.minY + 9, width: icon, height: icon))
        if running.contains(a.name) {
            rgb(20, 20, 25, 0.7).setFill()
            NSBezierPath(ovalIn: NSRect(x: dx + icon / 2 - 2, y: dock.minY + 2.5, width: 4, height: 4)).fill()
        }
        dx += icon + gap
    }
    rgb(20, 20, 25, 0.25).setFill(); NSRect(x: dx + divider / 2 - 3, y: dock.minY + 12, width: 1, height: icon - 6).fill()
    dx += divider
    if let trash = NSImage(named: NSImage.trashEmptyName) {
        trash.draw(in: NSRect(x: dx, y: dock.minY + 9, width: icon, height: icon))
    }
}

/// Blurred wallpaper for the dock's frosted glass (set before drawing a desktop).
var wallpaperBlur: CGImage?
func drawWallpaper(_ canvas: NSSize) {
    NSGradient(colors: [rgb(64, 110, 190), rgb(120, 96, 190), rgb(232, 140, 160)])!
        .draw(in: NSRect(origin: .zero, size: canvas), angle: -55)
}

// MARK: - The switcher overlay (light, frosted, like the real one)

struct Layout {
    var columns: Int, count: Int, cellW: CGFloat, cellH: CGFloat, icon: CGFloat
    let pad: CGFloat = 16, gap: CGFloat = 6
    var rows: Int { (count + columns - 1) / columns }
    var size: NSSize { NSSize(width: CGFloat(columns) * cellW + CGFloat(columns - 1) * gap + pad * 2,
                              height: CGFloat(rows) * cellH + CGFloat(rows - 1) * gap + pad * 2) }
    func cell(_ i: CGFloat, _ origin: NSPoint) -> NSRect {
        let col = i.truncatingRemainder(dividingBy: CGFloat(columns)), row = (i / CGFloat(columns)).rounded(.down)
        return NSRect(x: origin.x + pad + col * (cellW + gap), y: origin.y + size.height - pad - (row + 1) * cellH - row * gap,
                      width: cellW, height: cellH)
    }
}

func drawOverlay(_ l: Layout, at origin: NSPoint, items: [(MockApp, String)], highlight: NSRect, selected: Int, allLabels: Bool,
                 backdropBlur: CGImage, canvas: NSSize, alpha: CGFloat, zoom: CGFloat) {
    guard alpha > 0 else { return }
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)
    let frame = NSRect(origin: origin, size: l.size)
    ctx.translateBy(x: frame.midX, y: frame.midY); ctx.scaleBy(x: zoom, y: zoom); ctx.translateBy(x: -frame.midX, y: -frame.midY)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let shape = rounded(frame, 22)
    NSGraphicsContext.saveGraphicsState()
    // Kept small and light: a GIF's 256-colour palette turns big soft shadows into visible bands.
    let sh = NSShadow(); sh.shadowBlurRadius = 12; sh.shadowOffset = NSSize(width: 0, height: -3)
    sh.shadowColor = NSColor.black.withAlphaComponent(0.16); sh.set()
    NSColor.white.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Frosted glass: the blurred desktop behind, washed with white.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    ctx.draw(backdropBlur, in: CGRect(origin: .zero, size: canvas))
    // The real panel (macOS "popover" material) looks like an even light grey in light mode; a solid fill matches it
    // (any see-through blur turns into colour blotches in a 256-colour GIF).
    rgb(242, 242, 245, 1).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    rgb(0, 0, 0, 0.10).setStroke(); let border = rounded(frame.insetBy(dx: 0.5, dy: 0.5), 22); border.lineWidth = 1; border.stroke()
    rgb(0, 0, 0, 0.10).setFill(); rounded(highlight, 14).fill()
    for (i, item) in items.enumerated() {
        let c = l.cell(CGFloat(i), origin)
        let sel = i == selected
        let s = l.icon * (sel ? 1.06 : 1)
        let labelH: CGFloat = allLabels ? 30 : 15
        drawIcon(item.0, in: NSRect(x: c.midX - s / 2, y: c.maxY - 9 - s + (sel ? 1 : 0), width: s, height: s))
        if allLabels || sel {
            text(item.1, in: NSRect(x: c.minX + 5, y: c.minY + 6, width: c.width - 10, height: labelH), size: 11, weight: .medium,
                 color: rgb(25, 25, 30), align: .center, lines: allLabels ? 2 : 1)
        }
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: - Trackpad inset with three finger dots and a caption

func drawTrackpadInset(fingers: NSPoint?, fingerAlpha: CGFloat, caption: String) {
    // A slim strip between the switcher and the dock: a mini trackpad with three finger dots, then the caption.
    let card = NSRect(x: 400 - 130, y: 74, width: 260, height: 44)
    rgb(20, 20, 28, 0.72).setFill(); rounded(card, 12).fill()
    let pad = NSRect(x: card.minX + 9, y: card.minY + 7, width: 50, height: 30)
    rgb(255, 255, 255, 0.10).setFill(); rounded(pad, 5).fill()
    rgb(255, 255, 255, 0.40).setStroke(); let b = rounded(pad, 5); b.lineWidth = 1; b.stroke()
    if let f = fingers, fingerAlpha > 0 {
        for dx in [-6.5, 0.0, 6.5] {
            let p = NSPoint(x: pad.minX + f.x * pad.width + dx, y: pad.minY + f.y * pad.height + (dx == 0 ? 2 : 0))
            NSColor.white.withAlphaComponent(0.95 * fingerAlpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)).fill()
        }
    }
    text(caption, in: NSRect(x: pad.maxX + 10, y: card.minY + 13, width: card.maxX - pad.maxX - 18, height: 18), size: 12.5,
         weight: .semibold, color: .white, align: .left)
}

func ease(_ t: CGFloat) -> CGFloat { let c = max(0, min(1, t)); return 1 - pow(1 - c, 3) }
func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
    NSRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t, width: a.width, height: a.height)
}

// MARK: - 1. Animated demo

do {
    scale = 1
    let canvas = NSSize(width: 800, height: 500)
    wallpaperBlur = blurred(render(canvas) { drawWallpaper(canvas) }, radius: 20)
    let desktops: [Front: CGImage] = [.browser: render(canvas) { drawDesktop(canvas, front: .browser) },
                                      .notes: render(canvas) { drawDesktop(canvas, front: .notes) }]
    let blurs = desktops.mapValues { blurred($0, radius: 30) }
    // Windows mode, as the app draws it: a title under every tile (two lines), 64-pt icons, 150-pt tiles.
    let items: [(MockApp, String)] = [
        (browser, "Weekend recipes"), (mail, "Inbox (3)"), (notes, "Project ideas"), (photos, "Library"),
        (browser, "Trip planning"), (terminal, "~/projects — zsh"), (music, "Focus playlist"), (files, "Downloads"),
    ]
    let layout = Layout(columns: 4, count: items.count, cellW: 150, cellH: 64 + 21 + 28, icon: 64)
    let origin = NSPoint(x: (canvas.width - layout.size.width) / 2, y: (canvas.height - layout.size.height) / 2 + 20)

    // (time, selected, finger x/y on the pad, caption)
    let keys: [(t: Double, sel: Int, f: NSPoint, cap: String)] = [
        (0.30, 1, NSPoint(x: 0.36, y: 0.5), "Swipe right with 3 fingers"),
        (1.05, 2, NSPoint(x: 0.52, y: 0.5), "Keep swiping to move"),
        (1.55, 3, NSPoint(x: 0.68, y: 0.5), "Keep swiping to move"),
        (2.25, 2, NSPoint(x: 0.52, y: 0.5), "Swipe back to go back"),
        (3.05, 2, NSPoint(x: 0.52, y: 0.5), "Lift to switch"),
    ]
    let start = NSPoint(x: 0.2, y: 0.5)
    let lift = 3.25, end = 4.9, fps = 20.0
    var frames: [CGImage] = []
    var t = 0.0
    while t < end {
        let switched = t > lift + 0.08
        let desktop = switched ? desktops[.notes]! : desktops[.browser]!
        let k = keys.lastIndex { $0.t <= t }
        let cur = k.map { keys[$0] }, prev = k.flatMap { $0 > 0 ? keys[$0 - 1] : nil }
        let since = CGFloat((t - (cur?.t ?? 0)) / 0.18)
        let selected = cur.map { since > 0.5 || prev == nil ? $0.sel : prev!.sel } ?? 1
        let hl = cur.map { c in lerp(layout.cell(CGFloat(prev?.sel ?? c.sel), origin), layout.cell(CGFloat(c.sel), origin), prev == nil ? 1 : ease(since)) }
            ?? layout.cell(1, origin)
        let fFrom = prev?.f ?? start, fTo = cur?.f ?? start
        let ft = ease(CGFloat((t - (cur?.t ?? 0)) / 0.4))
        let finger = NSPoint(x: fFrom.x + (fTo.x - fFrom.x) * ft, y: fFrom.y + (fTo.y - fFrom.y) * ft)
        let fingerAlpha: CGFloat = t < lift ? ease(CGFloat(t / 0.2)) : max(0, 1 - CGFloat((t - lift) / 0.15))
        let open = ease(CGFloat((t - 0.30) / 0.18))
        let overlayAlpha: CGFloat = t < lift ? open : max(0, 1 - CGFloat((t - lift) / 0.15))
        let zoom: CGFloat = 0.96 + 0.04 * (t < lift ? open : 1)
        let caption = switched ? "Switched to Notes" : (cur?.cap ?? "Swipe right with 3 fingers")

        frames.append(render(canvas) {
            NSGraphicsContext.current!.cgContext.draw(desktop, in: CGRect(origin: .zero, size: canvas))
            drawOverlay(layout, at: origin, items: items, highlight: hl, selected: selected, allLabels: true,
                        backdropBlur: switched ? blurs[.notes]! : blurs[.browser]!, canvas: canvas, alpha: overlayAlpha, zoom: zoom)
            drawTrackpadInset(fingers: finger, fingerAlpha: fingerAlpha, caption: caption)
        })
        t += 1 / fps
    }
    let url = URL(fileURLWithPath: "\(outDir)/swipeswitch-demo.gif") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (i, f) in frames.enumerated() {
        let delay = i == frames.count - 1 ? 0.8 : 1 / fps
        CGImageDestinationAddImage(dest, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                                               kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
    publish("swipeswitch-demo", "gif")
}

// MARK: - 2. Windows mode (still image, retina)

do {
    scale = 2
    let canvas = NSSize(width: 800, height: 500)
    wallpaperBlur = blurred(render(canvas) { drawWallpaper(canvas) }, radius: 40)
    let desktop = render(canvas) { drawDesktop(canvas, front: .browser) }
    let items: [(MockApp, String)] = [
        (browser, "Weekend recipes"), (notes, "Project ideas"), (mail, "Inbox (3)"),
        (browser, "Trip planning"), (terminal, "~/projects — zsh"), (music, "Focus playlist"),
    ]
    let layout = Layout(columns: 6, count: items.count, cellW: 118, cellH: 64 + 21 + 28, icon: 64)
    let origin = NSPoint(x: (canvas.width - layout.size.width) / 2, y: (canvas.height - layout.size.height) / 2 + 10)
    let image = render(canvas) {
        NSGraphicsContext.current!.cgContext.draw(desktop, in: CGRect(origin: .zero, size: canvas))
        drawOverlay(layout, at: origin, items: items, highlight: layout.cell(3, origin), selected: 3, allLabels: true,
                    backdropBlur: blurred(desktop, radius: 30 * 2), canvas: canvas, alpha: 1, zoom: 1)
    }
    let url = URL(fileURLWithPath: "\(outDir)/windows-mode.png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
    publish("windows-mode", "png")
}
