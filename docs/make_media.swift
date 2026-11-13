// Draws the README's example images from scratch: made-up apps and generic symbol icons, never a real screen.
// Usage: swift docs/make_media.swift docs/images
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - Mock content

struct MockApp { let name: String; let symbol: String; let colors: (NSColor, NSColor) }
func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor { NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

let apps: [MockApp] = [
    MockApp(name: "Browser", symbol: "globe", colors: (rgb(66, 133, 244), rgb(30, 90, 200))),
    MockApp(name: "Mail", symbol: "envelope.fill", colors: (rgb(52, 170, 255), rgb(10, 110, 230))),
    MockApp(name: "Notes", symbol: "note.text", colors: (rgb(255, 214, 80), rgb(240, 170, 30))),
    MockApp(name: "Photos", symbol: "photo.fill", colors: (rgb(255, 120, 150), rgb(220, 60, 120))),
    MockApp(name: "Music", symbol: "music.note", colors: (rgb(255, 90, 100), rgb(210, 40, 70))),
    MockApp(name: "Terminal", symbol: "terminal.fill", colors: (rgb(70, 70, 80), rgb(30, 30, 36))),
    MockApp(name: "Calendar", symbol: "calendar", colors: (rgb(250, 250, 250), rgb(215, 215, 220))),
    MockApp(name: "Chat", symbol: "message.fill", colors: (rgb(80, 210, 120), rgb(30, 160, 80))),
    MockApp(name: "Files", symbol: "folder.fill", colors: (rgb(110, 190, 255), rgb(60, 140, 230))),
    MockApp(name: "Maps", symbol: "map.fill", colors: (rgb(120, 200, 140), rgb(60, 150, 100))),
]

// MARK: - Drawing helpers

func roundedRect(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

func drawIcon(_ app: MockApp, in r: NSRect) {
    let path = roundedRect(r, r.width * 0.23)
    NSGradient(starting: app.colors.0, ending: app.colors.1)!.draw(in: path, angle: -90)
    let symColor: NSColor = app.name == "Calendar" ? rgb(230, 60, 60) : .white
    let cfg = NSImage.SymbolConfiguration(pointSize: r.width * 0.42, weight: .semibold).applying(.init(paletteColors: [symColor]))
    if let sym = NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let s = sym.size
        sym.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height))
    }
}

func drawText(_ text: String, centeredIn r: NSRect, size: CGFloat, weight: NSFont.Weight = .medium, color: NSColor = .white, lines: Int = 1) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: para]
    NSAttributedString(string: text, attributes: attrs).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

func drawBackground(_ size: NSSize) {
    NSGradient(colors: [rgb(28, 36, 64), rgb(58, 42, 92), rgb(32, 52, 86)])!.draw(in: NSRect(origin: .zero, size: size), angle: -60)
}

/// The switcher panel: a frosted rounded rectangle with a grid of cells and a sliding highlight.
struct Panel {
    var columns: Int, rows: Int, cellW: CGFloat, cellH: CGFloat, icon: CGFloat
    let pad: CGFloat = 16, gap: CGFloat = 6
    var size: NSSize { NSSize(width: CGFloat(columns) * cellW + CGFloat(columns - 1) * gap + pad * 2,
                              height: CGFloat(rows) * cellH + CGFloat(rows - 1) * gap + pad * 2) }
    func cellRect(_ i: CGFloat, origin: NSPoint) -> NSRect {
        let col = i.truncatingRemainder(dividingBy: CGFloat(columns)), row = (i / CGFloat(columns)).rounded(.down)
        return NSRect(x: origin.x + pad + col * (cellW + gap),
                      y: origin.y + size.height - pad - (row + 1) * cellH - row * gap, width: cellW, height: cellH)
    }
}

func drawPanel(_ p: Panel, at origin: NSPoint, items: [(app: MockApp, title: String)], highlight: NSRect?, selected: Int,
               allLabels: Bool, alpha: CGFloat) {
    NSGraphicsContext.current?.saveGraphicsState()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAlpha(alpha)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let frame = NSRect(origin: origin, size: p.size)
    let shadow = NSShadow(); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.set()
    rgb(38, 38, 46).withAlphaComponent(0.92).setFill(); roundedRect(frame, 22).fill()
    NSShadow().set()
    NSColor.white.withAlphaComponent(0.10).setStroke(); let border = roundedRect(frame.insetBy(dx: 0.5, dy: 0.5), 22); border.lineWidth = 1; border.stroke()
    if let h = highlight { NSColor.white.withAlphaComponent(0.16).setFill(); roundedRect(h, 14).fill() }
    for (i, item) in items.enumerated() {
        let cell = p.cellRect(CGFloat(i), origin: origin)
        let isSel = i == selected
        let iconSize = p.icon * (isSel ? 1.06 : 1)
        let labelH: CGFloat = allLabels ? 30 : 15
        let iconRect = NSRect(x: cell.midX - iconSize / 2, y: cell.maxY - 8 - iconSize - (isSel ? -1 : 0), width: iconSize, height: iconSize)
        drawIcon(item.app, in: iconRect)
        if allLabels || isSel {
            drawText(item.title, centeredIn: NSRect(x: cell.minX + 6, y: cell.minY + 6, width: cell.width - 12, height: labelH),
                     size: 11, color: NSColor.white.withAlphaComponent(isSel ? 1 : 0.85), lines: allLabels ? 2 : 1)
        }
    }
    ctx.endTransparencyLayer()
    NSGraphicsContext.current?.restoreGraphicsState()
}

func drawTrackpad(center: NSPoint, fingers: NSPoint?, fingerAlpha: CGFloat) {
    let r = NSRect(x: center.x - 110, y: center.y - 62, width: 220, height: 124)
    NSColor.white.withAlphaComponent(0.08).setFill(); roundedRect(r, 14).fill()
    NSColor.white.withAlphaComponent(0.28).setStroke(); let b = roundedRect(r, 14); b.lineWidth = 1.5; b.stroke()
    guard let f = fingers, fingerAlpha > 0 else { return }
    for dx in [-22.0, 0.0, 22.0] {
        let p = NSPoint(x: r.minX + f.x * r.width + dx, y: r.minY + f.y * r.height + (dx == 0 ? 6 : 0))
        NSColor.white.withAlphaComponent(0.85 * fingerAlpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)).fill()
    }
}

func render(_ size: NSSize, scale: CGFloat = 1, _ draw: () -> Void) -> CGImage {
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

func writePNG(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}

func easeOut(_ t: CGFloat) -> CGFloat { let c = max(0, min(1, t)); return 1 - pow(1 - c, 3) }
func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
    NSRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t, width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
}

// MARK: - 1. Animated demo (apps, grid layout)

do {
    let canvas = NSSize(width: 720, height: 430)
    let panel = Panel(columns: 5, rows: 2, cellW: 88, cellH: 96, icon: 58)
    let origin = NSPoint(x: (canvas.width - panel.size.width) / 2, y: canvas.height - panel.size.height - 24)
    let items = apps.map { ($0, $0.name) }
    let pad = NSPoint(x: canvas.width / 2, y: 108)
    let fps = 25.0

    // (time, selected index, finger position on the pad 0...1, caption)
    let keyframes: [(t: Double, sel: Int, finger: NSPoint, caption: String)] = [
        (0.0, 1, NSPoint(x: 0.25, y: 0.5), "Swipe right with three fingers"),
        (1.0, 2, NSPoint(x: 0.42, y: 0.5), "Keep swiping to move"),
        (1.5, 3, NSPoint(x: 0.58, y: 0.5), "Keep swiping to move"),
        (2.0, 4, NSPoint(x: 0.74, y: 0.5), "Keep swiping to move"),
        (2.7, 9, NSPoint(x: 0.74, y: 0.22), "Swipe down for older apps"),
        (3.5, 9, NSPoint(x: 0.74, y: 0.22), "Lift your fingers to switch"),
    ]
    let total = 4.6
    var frames: [CGImage] = []
    var t = 0.0
    while t < total {
        let appear = easeOut(CGFloat((t - 0.35) / 0.25))           // overlay fades in after the swipe starts
        let fingersIn = easeOut(CGFloat(t / 0.25))
        let lift = 3.6
        let fingerAlpha = t < lift ? fingersIn : max(0, 1 - CGFloat((t - lift) / 0.2))
        let overlayAlpha = t < lift ? appear : max(0, 1 - CGFloat((t - lift) / 0.25))

        // Current and previous keyframe for the highlight and finger position.
        let k = keyframes.lastIndex { $0.t <= t } ?? 0
        let cur = keyframes[k], prev = keyframes[max(0, k - 1)]
        let since = CGFloat((t - cur.t) / 0.2)
        let hl = lerp(panel.cellRect(CGFloat(prev.sel), origin: origin), panel.cellRect(CGFloat(cur.sel), origin: origin), k == 0 ? 1 : easeOut(since))
        let fingerT = easeOut(CGFloat((t - cur.t) / 0.35))
        let fingerFrom = k == 0 ? NSPoint(x: 0.1, y: 0.5) : prev.finger
        let finger = NSPoint(x: fingerFrom.x + (cur.finger.x - fingerFrom.x) * fingerT, y: fingerFrom.y + (cur.finger.y - fingerFrom.y) * fingerT)
        let caption = t >= lift + 0.25 ? "Switched to Maps" : cur.caption

        frames.append(render(canvas) {
            drawBackground(canvas)
            if overlayAlpha > 0 {
                drawPanel(panel, at: origin, items: items, highlight: hl, selected: since > 0.5 || k == 0 ? cur.sel : prev.sel, allLabels: false, alpha: overlayAlpha)
            }
            drawTrackpad(center: pad, fingers: finger, fingerAlpha: fingerAlpha)
            drawText(caption, centeredIn: NSRect(x: 0, y: 14, width: canvas.width, height: 22), size: 15, weight: .semibold,
                     color: NSColor.white.withAlphaComponent(0.92))
        })
        t += 1 / fps
    }
    // Hold the last frame a moment before looping.
    let url = URL(fileURLWithPath: "\(outDir)/swipeswitch-demo.gif") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (i, f) in frames.enumerated() {
        let delay = i == frames.count - 1 ? 1.0 : 1 / fps
        CGImageDestinationAddImage(dest, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
    print("swipeswitch-demo.gif: \(frames.count) frames")
}

// MARK: - 2. Windows mode (still image)

do {
    let canvas = NSSize(width: 720, height: 300)
    let panel = Panel(columns: 4, rows: 2, cellW: 150, cellH: 104, icon: 52)
    let origin = NSPoint(x: (canvas.width - panel.size.width) / 2, y: (canvas.height - panel.size.height) / 2)
    let byName = Dictionary(uniqueKeysWithValues: apps.map { ($0.name, $0) })
    let items: [(app: MockApp, title: String)] = [
        (byName["Browser"]!, "Weekend recipes — Browser"),
        (byName["Mail"]!, "Inbox (3)"),
        (byName["Browser"]!, "Trip planning — Browser"),
        (byName["Notes"]!, "Project ideas"),
        (byName["Terminal"]!, "~/projects — zsh"),
        (byName["Files"]!, "Downloads"),
        (byName["Notes"]!, "Grocery list"),
        (byName["Music"]!, "Focus playlist"),
    ]
    let image = render(canvas, scale: 2) {
        drawBackground(canvas)
        drawPanel(panel, at: origin, items: items, highlight: panel.cellRect(2, origin: origin), selected: 2, allLabels: true, alpha: 1)
    }
    writePNG(image, "windows-mode.png")
    print("windows-mode.png")
}
