import Foundation
import QuartzCore

/// One summarized trackpad frame: how many fingers are touching and where their centroid is.
struct TouchFrame {
    var device: UInt
    var count: Int
    var x: Double   // 0 (left) ... 1 (right)
    var y: Double   // 0 (bottom) ... 1 (top)
    /// Every contact the trackpad reported, including fingers landing or lifting (not counted in `count`).
    var raw = 0
    /// When the trackpad delivered the frame (CACurrentMediaTime), before it waited for the main thread.
    var time = 0.0
}

/// Reads raw finger data from every trackpad through Apple's private MultitouchSupport framework.
/// This sees touches globally (including 3/4-finger swipes) without needing any permission.
final class MultitouchMonitor {
    static let shared = MultitouchMonitor()

    var onFrame: ((TouchFrame) -> Void)?

    private typealias CreateListFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias RegisterFn = @convention(c) (MTDeviceRef?, MTContactCallbackFunction?) -> Void
    private typealias StartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias StopFn = @convention(c) (MTDeviceRef?) -> Void

    private typealias DeviceIDFn = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias DimensionsFn = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    private typealias ActuatorCreateFn = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias ActuatorOpenFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ActuateFn = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32

    private var deviceID: DeviceIDFn?
    private var dimensions: DimensionsFn?
    private var actuatorCreate: ActuatorCreateFn?
    private var actuatorOpen: ActuatorOpenFn?
    private var actuatorClose: ActuatorOpenFn?
    private var actuate: ActuateFn?

    /// Hardware IDs of the trackpads we listen to, keyed by device pointer (as delivered in TouchFrame.device).
    private var deviceIDs: [UInt: UInt64] = [:]
    /// Physical surface size of each trackpad in millimetres, keyed like deviceIDs.
    private var sizes: [UInt: CGSize] = [:]
    /// Used when a trackpad doesn't report its size (roughly a 13-inch MacBook trackpad).
    static let fallbackSize = CGSize(width: 130, height: 80)
    private var actuators: [UInt64: UnsafeMutableRawPointer] = [:]
    /// The trackpad most recently touched (main thread).
    var lastTouchedDevice: UInt = 0

    private var createList: CreateListFn?
    private var register: RegisterFn?
    private var unregister: RegisterFn?
    private var startDevice: StartFn?
    private var stopDevice: StopFn?

    private var deviceList: CFArray?
    private var devices: [MTDeviceRef] = []
    private(set) var isLoaded = false

    var deviceCount: Int { devices.count }

    private init() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else {
            NSLog("SwipeSwitch: could not load MultitouchSupport")
            return
        }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        createList = sym("MTDeviceCreateList", CreateListFn.self)
        register = sym("MTRegisterContactFrameCallback", RegisterFn.self)
        unregister = sym("MTUnregisterContactFrameCallback", RegisterFn.self)
        startDevice = sym("MTDeviceStart", StartFn.self)
        stopDevice = sym("MTDeviceStop", StopFn.self)
        deviceID = sym("MTDeviceGetDeviceID", DeviceIDFn.self)
        dimensions = sym("MTDeviceGetSensorSurfaceDimensions", DimensionsFn.self)
        actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreateFn.self)
        actuatorOpen = sym("MTActuatorOpen", ActuatorOpenFn.self)
        actuatorClose = sym("MTActuatorClose", ActuatorOpenFn.self)
        actuate = sym("MTActuatorActuate", ActuateFn.self)
        isLoaded = createList != nil && register != nil && startDevice != nil
    }

    private func copyDeviceList() -> CFArray? {
        guard let raw = createList?() else { return nil }
        return Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
    }

    @discardableResult
    func start() -> Int {
        guard isLoaded, devices.isEmpty, let list = copyDeviceList() else { return devices.count }
        deviceList = list
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            // Skip touch strips such as the Touch Bar (a few mm tall); keep real trackpads.
            var w: Int32 = 0, h: Int32 = 0
            if dimensions?(dev, &w, &h) == 0, h > 0, h < 3000 { continue }
            if w > 0, h > 0 { sizes[UInt(bitPattern: dev)] = CGSize(width: Double(w) / 100, height: Double(h) / 100) }
            var hwID: UInt64 = 0
            if deviceID?(dev, &hwID) == 0 { deviceIDs[UInt(bitPattern: dev)] = hwID }
            register?(dev, contactCallback)
            startDevice?(dev, 0)
            devices.append(dev)
        }
        return devices.count
    }

    func stop() {
        for dev in devices {
            unregister?(dev, contactCallback)
            stopDevice?(dev)
        }
        devices.removeAll()
        deviceList = nil
        for a in actuators.values { _ = actuatorClose?(a) }
        actuators.removeAll()
        deviceIDs.removeAll()
        sizes.removeAll()
    }

    /// Physical size (mm) of the trackpad a frame came from.
    func surfaceSize(of device: UInt) -> CGSize { sizes[device] ?? Self.fallbackSize }

    func restart() {
        stop()
        start()
    }

    /// Clicks the trackpad's haptic motor directly. Unlike NSHapticFeedbackManager this works while another
    /// app is in front. Strength is an actuation pattern ID (higher is stronger). Returns false if unsupported.
    @discardableResult
    func haptic(strength: Int32) -> Bool {
        guard let actuatorCreate, let actuatorOpen, let actuate else { return false }
        var candidates: [UInt64] = []
        if let id = deviceIDs[lastTouchedDevice] { candidates.append(id) }
        candidates += deviceIDs.values.filter { !candidates.contains($0) }
        for id in candidates {
            var act = actuators[id]
            if act == nil, let created = actuatorCreate(id), actuatorOpen(created) == 0 {
                actuators[id] = created
                act = created
            }
            if let act, actuate(act, strength, 0, 0, 0) == 0 { return true }
        }
        return false
    }

    private var lastLagNote = 0.0

    /// Diagnostics: frames that waited a long time for the main thread. A busy main thread can open and close the
    /// switcher in one go once it catches up, so the overlay is never drawn.
    func noteLag(_ lag: Double) {
        guard lag > 0.05, SessionLog.enabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastLagNote > 0.5 else { return }
        lastLagNote = now
        SessionLog.problem("touch input waited \(Int(lag * 1000)) ms for the main thread")
    }

    /// Number of trackpads currently attached (used to notice a Magic Trackpad being connected).
    func attachedDeviceCount() -> Int {
        guard let list = copyDeviceList() else { return 0 }
        var n = 0
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            var w: Int32 = 0, h: Int32 = 0
            if dimensions?(UnsafeMutableRawPointer(mutating: raw), &w, &h) == 0, h > 0, h < 3000 { continue }
            n += 1
        }
        return n
    }
}

private let contactCallback: MTContactCallbackFunction = { device, touches, count, _, _ in
    var n = 0
    var sx = 0.0, sy = 0.0
    if let touches = touches {
        for i in 0..<Int(count) {
            let t = touches[i]
            if t.state == 4 || t.state == 5 {
                n += 1
                sx += Double(t.normalized.position.x)
                sy += Double(t.normalized.position.y)
            }
        }
    }
    let frame = TouchFrame(device: UInt(bitPattern: device),
                           count: n,
                           x: n > 0 ? sx / Double(n) : 0,
                           y: n > 0 ? sy / Double(n) : 0,
                           raw: Int(count), time: CACurrentMediaTime())
    DispatchQueue.main.async {
        let monitor = MultitouchMonitor.shared
        if frame.time > 0 { monitor.noteLag(CACurrentMediaTime() - frame.time) }
        if frame.count > 0 { monitor.lastTouchedDevice = frame.device }
        monitor.onFrame?(frame)
    }
    return 0
}
