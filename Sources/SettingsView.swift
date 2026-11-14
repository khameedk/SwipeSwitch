import AppKit
import ServiceManagement
import SwiftUI

final class SettingsStatus: ObservableObject {
    @Published var axTrusted = AXIsProcessTrusted()
    @Published var conflict: String?
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var loginError: String?
    @Published var screenRecording = CGPreflightScreenCaptureAccess()
}

struct SettingsView: View {
    @AppStorage(Prefs.Key.enabled) private var enabled = true
    @AppStorage(Prefs.Key.fingers) private var fingers = 3
    @AppStorage(Prefs.Key.direction) private var direction: SwipeDirection = .right
    @AppStorage(Prefs.Key.step) private var step = 8.0
    @AppStorage(Prefs.Key.activation) private var activation = 4.0
    @AppStorage(Prefs.Key.bttIntegration) private var bttIntegration = false
    @AppStorage(Prefs.Key.keyboardTrigger) private var keyboardTrigger = false
    @AppStorage(Prefs.Key.diagnosticLogging) private var diagnosticLogging = false
    @AppStorage(Prefs.Key.diagnosticLoggingUntil) private var diagnosticLoggingUntil = 0.0
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.scope) private var scope: Scope = .all
    @AppStorage(Prefs.Key.maxApps) private var maxApps = 24
    @AppStorage(Prefs.Key.layout) private var layout: Layout = .grid
    @AppStorage(Prefs.Key.columns) private var columns = 6
    @AppStorage(Prefs.Key.iconSize) private var iconSize = 64.0
    @AppStorage(Prefs.Key.appearSpeed) private var appearSpeed: AppearSpeed = .quick
    @AppStorage(Prefs.Key.showAllNames) private var showAllNames = false
    @AppStorage(Prefs.Key.wrap) private var wrap = false
    @AppStorage(Prefs.Key.excluded) private var excludedRaw = ""
    @AppStorage(Prefs.Key.mode) private var mode: SwitchMode = .apps
    @AppStorage(Prefs.Key.includeMinimized) private var includeMinimized = true
    @AppStorage(Prefs.Key.includeHidden) private var includeHidden = true
    @AppStorage(Prefs.Key.sort) private var sort: SortOrder = .recent
    @AppStorage(Prefs.Key.hapticStrength) private var hapticStrength: HapticStrength = .medium

    @ObservedObject var status: SettingsStatus
    @StateObject private var bttSetup = BTTSetupModel()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var excluded: [String] { excludedRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        Form {
            Section {
                Toggle("Enable swipe switching", isOn: $enabled)
                Toggle("Launch at login", isOn: Binding(get: { status.loginStatus == .enabled }, set: setLaunchAtLogin))
                if status.loginStatus == .requiresApproval {
                    note("Approve SwipeSwitch in System Settings › General › Login Items.")
                }
                if let err = status.loginError { note(err, color: .red) }
            }

            Section("Gesture") {
                Picker("Fingers", selection: $fingers) {
                    Text("Three").tag(3)
                    Text("Four").tag(4)
                }
                .pickerStyle(.segmented)
                Picker("Start by swiping", selection: $direction) {
                    Text("Right").tag(SwipeDirection.right)
                    Text("Left").tag(SwipeDirection.left)
                }
                .pickerStyle(.segmented)
                LabeledContent("Swipe distance to open") {
                    HStack {
                        Slider(value: $activation, in: 2...12, step: 1)
                        Text("\(Int(activation)) mm").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    .frame(width: 240)
                }
                LabeledContent("Swipe distance per step") {
                    HStack {
                        Slider(value: $step, in: 4...16, step: 1)
                        Text("\(Int(step)) mm").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    .frame(width: 240)
                }
                Toggle("Haptic feedback on each step", isOn: $haptics)
                LabeledContent("Haptic strength") {
                    HStack {
                        Picker("", selection: $hapticStrength) {
                            Text("Light").tag(HapticStrength.light)
                            Text("Medium").tag(HapticStrength.medium)
                            Text("Strong").tag(HapticStrength.strong)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Button("Test") { MultitouchMonitor.shared.haptic(strength: hapticStrength.actuationID) }
                    }
                }
                .disabled(!haptics)
                if let conflict = status.conflict {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(conflict, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        Button("Open Trackpad Settings…") { Activator.openTrackpadSettings() }
                    }
                }
                note(howItWorks)
            }

            Section("Keyboard") {
                Toggle("Open with ⌘Tab (replaces the macOS app switcher)", isOn: $keyboardTrigger)
                note("Hold ⌘ and press Tab to open it on the next app. While ⌘ is held: Tab moves forward, Shift moves back, arrow keys move around, Esc cancels. Release ⌘ to switch. Needs Accessibility access.")
                if keyboardTrigger && altTabRunning {
                    note("AltTab is running and also uses ⌘Tab. Quit it or change its shortcut, or both switchers will open.", color: .orange)
                }
            }

            Section("Switching") {
                Picker("Switch between", selection: $mode) {
                    Text("Apps").tag(SwitchMode.apps)
                    Text("Windows").tag(SwitchMode.windows)
                }
                .pickerStyle(.segmented)
                Picker("Show \(mode == .apps ? "apps" : "windows") from", selection: $scope) {
                    Text("All desktops").tag(Scope.all)
                    Text("Current desktop").tag(Scope.current)
                }
                Picker("Sort by", selection: $sort) {
                    Text("Last active").tag(SortOrder.recent)
                    Text("Name").tag(SortOrder.name)
                }
                .pickerStyle(.segmented)
                Toggle("Include minimized windows", isOn: $includeMinimized)
                Toggle("Include windows of hidden apps", isOn: $includeHidden)
                note(mode == .apps
                     ? "Apps without an open window are never shown. These options decide whether minimized or hidden windows count."
                     : "Minimized windows and hidden apps' windows appear faded.")
                if mode == .windows {
                    if !status.axTrusted {
                        note("Windows mode needs Accessibility access (see Status below) to read titles and pick the exact window.", color: .orange)
                    }
                }
                Stepper("Show up to \(maxApps) \(mode == .apps ? "apps" : "windows")", value: $maxApps, in: 4...60)
                LabeledContent("Excluded apps") {
                    Menu("Add…") {
                        ForEach(addableApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                                if let id = app.bundleIdentifier { setExcluded(excluded + [id]) }
                            }
                        }
                    }
                    .fixedSize()
                }
                ForEach(excluded, id: \.self) { id in
                    HStack {
                        Image(nsImage: Self.icon(for: id)).resizable().frame(width: 18, height: 18)
                        Text(Self.name(for: id))
                        Spacer()
                        Button { setExcluded(excluded.filter { $0 != id }) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Appearance") {
                Picker("Layout", selection: $layout) {
                    Text("Grid: newest on top row").tag(Layout.grid)
                    Text("Single row").tag(Layout.row)
                }
                Stepper("Columns: \(columns)", value: $columns, in: 3...12)
                    .disabled(layout == .row)
                LabeledContent("Icon size") {
                    Slider(value: $iconSize, in: 40...112, step: 8).frame(width: 220)
                }
                Toggle("Show names under every app", isOn: $showAllNames)
                    .disabled(mode == .windows)
                Picker("Show and hide the switcher", selection: $appearSpeed) {
                    Text("Instantly").tag(AppearSpeed.instant)
                    Text("Quickly").tag(AppearSpeed.quick)
                    Text("Smoothly").tag(AppearSpeed.smooth)
                }
                Toggle("Wrap around at the ends", isOn: $wrap)
            }

            Section("BetterTouchTool") {
                Toggle("Tell BetterTouchTool while the switcher is open", isOn: $bttIntegration)
                    .onChange(of: bttIntegration) { on in if on { bttSetup.check(ask: true) } }
                if bttIntegration {
                    LabeledContent("Shared secret") {
                        // Kept in the Keychain (BTTSecret), not in preferences.
                        SecureField("Optional", text: Binding(get: { BTTSecret.value }, set: { BTTSecret.set($0) }))
                            .frame(width: 200)
                    }
                    if BetterTouchTool.externalScriptingAllowed == false {
                        note("In BetterTouchTool, turn on Settings › Scripting BTT › “Allow external BetterTouchTool Scripting”.", color: .red)
                    }
                    BTTSetupRows(model: bttSetup, fingers: fingers)
                        .onAppear { bttSetup.check(ask: false) }
                }
                note("Sets the BTT variable “\(BetterTouchTool.variable)” to 1 while the switcher is open and 0 when it closes. BTT skips any gesture that has the condition “\(BetterTouchTool.variable) is not 1”; SwipeSwitch can add that condition to your BTT swipe gestures for you. macOS asks once to let SwipeSwitch control BetterTouchTool. Only used while BTT is running. See the README for details.")
            }

            Section("Status") {
                HStack {
                    Label(status.axTrusted ? "Accessibility access granted" : "Accessibility access needed",
                          systemImage: status.axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status.axTrusted ? .green : .orange)
                    Spacer()
                    if !status.axTrusted {
                        Button("Grant…") {
                            Activator.promptForAccessibility()
                            Activator.openAccessibilitySettings()
                        }
                    }
                }
                note("Used to bring the app or window you land on to the front, including ones on other desktops, and to read window titles.")
                if mode == .windows {
                    HStack {
                        Label(status.screenRecording ? "Screen Recording granted" : "Screen Recording (optional)",
                              systemImage: status.screenRecording ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(status.screenRecording ? .green : .secondary)
                        Spacer()
                        if !status.screenRecording {
                            Button("Grant…") { Activator.openScreenRecordingSettings() }
                        }
                    }
                    note("Without it, windows on other desktops show their app name until you've visited them once. SwipeSwitch never records your screen.")
                }
            }

            Section("Diagnostics") {
                Toggle("Log switcher activity (for troubleshooting)", isOn: $diagnosticLogging)
                    .onChange(of: diagnosticLogging) { SessionLog.settingChanged(on: $0) }
                if diagnosticLogging, diagnosticLoggingUntil > 0 {
                    note("Turns itself off at \(Date(timeIntervalSince1970: diagnosticLoggingUntil).formatted(date: .omitted, time: .shortened)).")
                }
                note("Turn it on while a problem is happening; it turns itself off after an hour. Records each switch (when it opened, how the swipe ended, which app it switched to, whether it landed, and any step that was slow) in macOS's log on this Mac. App names only: no keystrokes or window titles.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") { Prefs.reset() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 720)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in if settingsWindowVisible { refresh() } }
        .onChange(of: fingers) { _ in
            refresh()
            if bttIntegration { bttSetup.check(ask: false) }
        }
    }

    private var altTabRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.lwouis.alt-tab-macos").isEmpty
    }

    private var howItWorks: String {
        let f = fingers == 4 ? "four" : "three"
        let back = direction == .right ? "left" : "right"
        let down = layout == .grid ? " In the grid, swipe down for older apps." : ""
        return "Swipe \(direction.rawValue) with \(f) fingers to open the switcher; keep swiping to move, or swipe \(back) to go back.\(down) Lift your fingers to switch."
    }

    private var addableApps: [NSRunningApplication] {
        let ex = Set(excluded)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { app in
                guard let id = app.bundleIdentifier, !ex.contains(id), id != Bundle.main.bundleIdentifier else { return false }
                return seen.insert(id).inserted
            }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func setExcluded(_ ids: [String]) { excludedRaw = ids.joined(separator: "\n") }

    /// Re-checks permissions. Only assigns values that changed, so the form isn't redrawn every second.
    private func refresh() {
        func update<T: Equatable>(_ path: ReferenceWritableKeyPath<SettingsStatus, T>, _ value: T) {
            if status[keyPath: path] != value { status[keyPath: path] = value }
        }
        update(\.axTrusted, AXIsProcessTrusted())
        update(\.conflict, Prefs.gestureConflict(fingers: fingers))
        update(\.loginStatus, SMAppService.mainApp.status)
        update(\.screenRecording, CGPreflightScreenCaptureAccess())
    }

    /// The once-a-second check only matters while the Settings window is on screen.
    private var settingsWindowVisible: Bool {
        NSApp.windows.contains { $0.title == "SwipeSwitch Settings" && $0.isVisible }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            status.loginError = nil
        } catch {
            status.loginError = error.localizedDescription
        }
        status.loginStatus = SMAppService.mainApp.status
    }

    private func note(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    static func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}
