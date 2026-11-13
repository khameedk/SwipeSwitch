// Draws the README's example images from scratch: a made-up desktop, made-up apps and generic symbol icons.
// Nothing is captured from a real screen.
// Usage: swift docs/make_media.swift docs/images
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - Mock apps

struct MockApp { let name: String; let symbol: String; let top: NSColor; let bottom: NSColor; var glyph: NSColor = .white }
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let browser = MockApp(name: "Browser", symbol: "globe", top: rgb(80, 150, 250), bottom: rgb(30, 95, 215))
let mail = MockApp(name: "Mail", symbol: "envelope.fill", top: rgb(70, 185, 255), bottom: rgb(15, 115, 235))
let notes = MockApp(name: "Notes", symbol: "note.text", top: rgb(255, 222, 95), bottom: rgb(245, 175, 35))
let photos = MockApp(name: "Photos", symbol: "photo.fill", top: rgb(255, 135, 160), bottom: rgb(225, 65, 125))
let music = MockApp(name: "Music", symbol: "music.note", top: rgb(255, 100, 110), bottom: rgb(215, 45, 75))
let terminal = MockApp(name: "Terminal", symbol: "terminal.fill", top: rgb(85, 85, 95), bottom: rgb(35, 35, 42))
let calendar = MockApp(name: "Calendar", symbol: "calendar", top: rgb(255, 255, 255), bottom: rgb(220, 220, 226), glyph: rgb(230, 60, 60))
let chat = MockApp(name: "Chat", symbol: "message.fill", top: rgb(95, 220, 130), bottom: rgb(35, 165, 85))
let files = MockApp(name: "Files", symbol: "folder.fill", top: rgb(120, 200, 255), bottom: rgb(65, 145, 235))
let maps = MockApp(name: "Maps", symbol: "map.fill", top: rgb(130, 210, 150), bottom: rgb(65, 155, 105))
let allApps = [browser, mail, notes, photos, music, terminal, calendar, chat, files, maps]

// MARK: - Drawing helpers

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

func drawIcon(_ app: MockApp, in r: NSRect) {
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
    // Wallpaper
    NSGradient(colors: [rgb(64, 110, 190), rgb(120, 96, 190), rgb(232, 140, 160)])!
        .draw(in: NSRect(origin: .zero, size: canvas), angle: -55)
    // Menu bar
    let mb = NSRect(x: 0, y: canvas.height - 24, width: canvas.width, height: 24)
    rgb(255, 255, 255, 0.55).setFill(); mb.fill()
    let appName = front == .browser ? "Browser" : "Notes"
    text(appName, in: NSRect(x: 16, y: mb.minY + 4, width: 80, height: 16), size: 12.5, weight: .bold, color: rgb(20, 20, 25))
    var x: CGFloat = 16 + (front == .browser ? 62 : 50)
    for item in ["File", "Edit", "View", "Window", "Help"] {
        text(item, in: NSRect(x: x, y: mb.minY + 4, width: 60, height: 16), size: 12.5, color: rgb(20, 20, 25))
        x += CGFloat(item.count) * 7.5 + 16
    }
    text("Fri 10:12", in: NSRect(x: canvas.width - 90, y: mb.minY + 4, width: 76, height: 16), size: 12.5, color: rgb(20, 20, 25), align: .right)

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

    // Dock
    let dockApps = [browser, mail, notes, photos, music, terminal, calendar, chat, files, maps]
    let icon: CGFloat = 40, gap: CGFloat = 8
    let dockW = CGFloat(dockApps.count) * (icon + gap) + gap
    let dock = NSRect(x: (canvas.width - dockW) / 2, y: 8, width: dockW, height: icon + 16)
    rgb(255, 255, 255, 0.35).setFill(); rounded(dock, 16).fill()
    rgb(255, 255, 255, 0.5).setStroke(); let db = rounded(dock.insetBy(dx: 0.5, dy: 0.5), 16); db.lineWidth = 1; db.stroke()
    for (i, a) in dockApps.enumerated() { drawIcon(a, in: NSRect(x: dock.minX + gap + CGFloat(i) * (icon + gap), y: dock.minY + 8, width: icon, height: icon)) }
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
    rgb(246, 246, 248, 0.82).setFill(); shape.fill()
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
    let card = NSRect(x: 18, y: 84, width: 176, height: 136)
    rgb(20, 20, 28, 0.72).setFill(); rounded(card, 14).fill()
    let pad = NSRect(x: card.minX + 18, y: card.minY + 38, width: card.width - 36, height: 82)
    rgb(255, 255, 255, 0.10).setFill(); rounded(pad, 9).fill()
    rgb(255, 255, 255, 0.35).setStroke(); let b = rounded(pad, 9); b.lineWidth = 1.2; b.stroke()
    if let f = fingers, fingerAlpha > 0 {
        for dx in [-16.0, 0.0, 16.0] {
            let p = NSPoint(x: pad.minX + f.x * pad.width + dx, y: pad.minY + f.y * pad.height + (dx == 0 ? 5 : 0))
            NSColor.white.withAlphaComponent(0.9 * fingerAlpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)).fill()
        }
    }
    text(caption, in: NSRect(x: card.minX + 8, y: card.minY + 10, width: card.width - 16, height: 20), size: 11.5, weight: .semibold,
         color: .white, align: .center)
}

func ease(_ t: CGFloat) -> CGFloat { let c = max(0, min(1, t)); return 1 - pow(1 - c, 3) }
func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
    NSRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t, width: a.width, height: a.height)
}

// MARK: - 1. Animated demo

do {
    scale = 1
    let canvas = NSSize(width: 800, height: 500)
    let desktops: [Front: CGImage] = [.browser: render(canvas) { drawDesktop(canvas, front: .browser) },
                                      .notes: render(canvas) { drawDesktop(canvas, front: .notes) }]
    let blurs = desktops.mapValues { blurred($0, radius: 30) }
    let items = allApps.map { ($0, $0.name) }
    let layout = Layout(columns: 5, count: items.count, cellW: 92, cellH: 98, icon: 60)
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
            drawOverlay(layout, at: origin, items: items, highlight: hl, selected: selected, allLabels: false,
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
    print("swipeswitch-demo.gif: \(frames.count) frames")
}

// MARK: - 2. Windows mode (still image, retina)

do {
    scale = 2
    let canvas = NSSize(width: 800, height: 500)
    let desktop = render(canvas) { drawDesktop(canvas, front: .browser) }
    let items: [(MockApp, String)] = [
        (browser, "Weekend recipes — Browser"), (notes, "Project ideas"), (mail, "Inbox (3)"),
        (browser, "Trip planning — Browser"), (terminal, "~/projects — zsh"), (music, "Focus playlist"),
    ]
    let layout = Layout(columns: 6, count: items.count, cellW: 118, cellH: 108, icon: 56)
    let origin = NSPoint(x: (canvas.width - layout.size.width) / 2, y: (canvas.height - layout.size.height) / 2 + 10)
    let image = render(canvas) {
        NSGraphicsContext.current!.cgContext.draw(desktop, in: CGRect(origin: .zero, size: canvas))
        drawOverlay(layout, at: origin, items: items, highlight: layout.cell(3, origin), selected: 3, allLabels: true,
                    backdropBlur: blurred(desktop, radius: 30 * 2), canvas: canvas, alpha: 1, zoom: 1)
    }
    let url = URL(fileURLWithPath: "\(outDir)/windows-mode.png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
    print("windows-mode.png")
}
