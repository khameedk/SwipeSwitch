import Foundation
import QuartzCore

/// Turns raw finger frames into: begin (swipe started), step(dx, dy) as the fingers travel, and end (fingers lifted).
final class SwipeGestureRecognizer {
    var onBegin: (() -> Bool)?
    /// Fingers just touched down (the swipe may or may not follow): a chance to prepare ahead of time.
    var onTouchDown: (() -> Void)?
    var onStep: ((Int, Int) -> Void)?
    var onEnd: (() -> Void)?

    /// Whether vertical travel should produce steps (grid layout).
    var allowVertical = true

    private enum Phase { case idle, tracking, rejected, active }
    private var phase: Phase = .idle
    private var device: UInt = 0
    private var startX = 0.0, startY = 0.0
    private var anchorX = 0.0, anchorY = 0.0
    private var lastCount = 0
    private var lowCountSince: Double?
    private var lastFrameTime = 0.0
    private var watchdog: Timer?

    var isActive: Bool { phase == .active }

    func handle(_ f: TouchFrame) {
        let now = CACurrentMediaTime()
        if phase != .idle && f.device != device { return }
        if phase == .idle && !Prefs.enabled { return }
        lastFrameTime = now

        let n = Prefs.fingerCount
        // Work in millimetres so every trackpad size feels the same.
        // Transform so +x is always "forward" (older apps) and +y is "down".
        let size = MultitouchMonitor.shared.surfaceSize(of: f.device)
        let sign: Double = Prefs.direction == .left ? -1 : 1
        let tx = f.x * size.width * sign
        let ty = -f.y * size.height

        switch phase {
        case .idle:
            if f.count == n {
                phase = .tracking
                device = f.device
                startX = tx; startY = ty
                armWatchdog()
                onTouchDown?()
            }

        case .tracking:
            if f.count != n {
                if f.count > n { phase = .rejected } else { reset() }
                return
            }
            let dx = tx - startX, dy = ty - startY
            let act = Prefs.activationMillimetres
            if abs(dy) > act && abs(dy) > abs(dx) {
                phase = .rejected            // vertical swipe: leave it to macOS
            } else if dx < -act {
                phase = .rejected            // wrong direction
            } else if dx > act && dx > abs(dy) {
                if onBegin?() == true {
                    phase = .active
                    anchorX = tx; anchorY = ty
                    lastCount = n
                    lowCountSince = nil
                } else {
                    phase = .rejected
                }
            }

        case .rejected:
            if f.count == 0 { reset() }

        case .active:
            if f.count == n {
                if lastCount != n { anchorX = tx; anchorY = ty }   // re-anchor after a finger blip
                lowCountSince = nil
                stepIfNeeded(tx: tx, ty: ty)
            } else if f.count == 0 {
                finish("fingers lifted"); return
            } else if f.count < n {
                // Fingers rarely lift at exactly the same instant; give a short grace period.
                if let since = lowCountSince {
                    if now - since > 0.08 { finish("fingers lifted (one at a time)"); return }
                } else {
                    lowCountSince = now
                }
            }
            lastCount = f.count
        }
    }

    private func stepIfNeeded(tx: Double, ty: Double) {
        let stepX = Prefs.stepMillimetres
        let stepY = stepX
        let ddx = tx - anchorX, ddy = ty - anchorY
        let kx = Int(ddx / stepX)
        let ky = allowVertical ? Int(ddy / stepY) : 0
        if kx != 0 && abs(ddx) / stepX >= abs(ddy) / stepY {
            anchorX += Double(kx) * stepX
            anchorY = ty
            onStep?(kx, 0)
        } else if ky != 0 {
            anchorY += Double(ky) * stepY
            anchorX = tx
            onStep?(0, ky)
        } else if !allowVertical {
            anchorY = ty
        }
    }

    /// Drops the current swipe (e.g. Esc was pressed): the rest of it, including lifting the fingers, is ignored.
    func abandon() {
        if phase == .active { phase = .rejected }
    }

    /// Feed frames from code (used by the demo mode).
    func simulate(_ f: TouchFrame) { handle(f) }

    private func finish(_ reason: String) {
        SessionLog.note("swipe ended: \(reason)")
        reset()
        onEnd?()
    }

    private func reset() {
        phase = .idle
        lowCountSince = nil
        watchdog?.invalidate()
        watchdog = nil
    }

    /// Frames stop arriving once every finger is off the pad, so treat silence as a lift.
    private func armWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if CACurrentMediaTime() - self.lastFrameTime > 0.2 {
                if self.phase == .active { self.finish("touch frames stopped (watchdog)") } else { self.reset() }
            }
        }
    }
}
