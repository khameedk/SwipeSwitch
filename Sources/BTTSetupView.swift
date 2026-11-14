import SwiftUI

/// State for the "BTT gestures" rows in Settings › BetterTouchTool. All BTT calls run off the main thread.
final class BTTSetupModel: ObservableObject {
    @Published var gestures: [BTTGestureSetup.Gesture]?
    @Published var busy: String?
    @Published var message: String?
    @Published var isError = false
    @Published var confirmAdd = false
    @Published var confirmRemove = false

    var missing: [BTTGestureSetup.Gesture] { gestures?.filter { !$0.hasOurCondition } ?? [] }
    var covered: [BTTGestureSetup.Gesture] { gestures?.filter(\.hasOurCondition) ?? [] }

    /// Looks at BTT's swipe gestures. `ask`: may show macOS's permission prompt, and offers to add the condition if
    /// some gestures are missing it (used right after the option is turned on).
    func check(ask: Bool) {
        guard busy == nil else { return }
        guard BetterTouchTool.isRunning else {
            gestures = nil
            show("Open BetterTouchTool, then click Check.", error: false)
            return
        }
        guard ask || BetterTouchTool.hasPermission(ask: false) else { return }   // don't prompt just for opening Settings
        busy = "Checking BetterTouchTool…"
        let fingers = Prefs.fingerCount
        DispatchQueue.global(qos: .userInitiated).async {
            guard BetterTouchTool.hasPermission(ask: ask) else {
                self.finish(nil, "SwipeSwitch isn't allowed to control BetterTouchTool. Allow it in System Settings › Privacy & Security › Automation.", error: true)
                return
            }
            do {
                let found = try BTTGestureSetup.scan(fingers: fingers)
                self.finish(found, nil, error: false)
                DispatchQueue.main.async { if ask, !self.missing.isEmpty { self.confirmAdd = true } }
            } catch {
                self.finish(nil, "\(error)", error: true)
            }
        }
    }

    func addCondition() { run("Adding", missing) { try BTTGestureSetup.add(to: $0, progress: $1) } done: { "Added the condition to \($0) gesture\($0 == 1 ? "" : "s")." } }

    func removeCondition() { run("Removing", covered) { try BTTGestureSetup.remove(from: $0, progress: $1) } done: { "Took the condition out of \($0) gesture\($0 == 1 ? "" : "s")." } }

    private func run(_ verb: String, _ targets: [BTTGestureSetup.Gesture],
                     _ work: @escaping ([BTTGestureSetup.Gesture], (Int) -> Void) throws -> Int,
                     done: @escaping (Int) -> String) {
        guard busy == nil, !targets.isEmpty else { return }
        busy = "\(verb)… 0 of \(targets.count)"
        let fingers = Prefs.fingerCount
        DispatchQueue.global(qos: .userInitiated).async {
            var text: String
            var error = false
            do {
                let n = try work(targets) { n in DispatchQueue.main.async { self.busy = "\(verb)… \(n) of \(targets.count)" } }
                text = done(n)
            } catch let e {
                text = "\(e)"
                error = true
            }
            let found = try? BTTGestureSetup.scan(fingers: fingers)   // show the real state afterwards
            self.finish(found, text, error: error)
        }
    }

    private func finish(_ found: [BTTGestureSetup.Gesture]?, _ text: String?, error: Bool) {
        DispatchQueue.main.async {
            if let found { self.gestures = found }
            self.busy = nil
            self.show(text, error: error)
        }
    }

    private func show(_ text: String?, error: Bool) {
        message = text
        isError = error
    }
}

/// The rows under the BetterTouchTool toggle: how many swipe gestures have the condition, and buttons to add or remove it.
struct BTTSetupRows: View {
    @ObservedObject var model: BTTSetupModel
    let fingers: Int

    var body: some View {
        LabeledContent("BTT swipes with the condition") {
            HStack {
                if let busy = model.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).foregroundStyle(.secondary)
                } else {
                    Text(summary).foregroundStyle(.secondary)
                    Button("Check") { model.check(ask: true) }
                }
            }
        }
        .alert("Add the condition to \(model.missing.count) BetterTouchTool gesture\(model.missing.count == 1 ? "" : "s")?",
               isPresented: $model.confirmAdd) {
            Button("Add") { model.addCondition() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("BTT will skip these gestures while the SwipeSwitch switcher is open; at other times they work as before. Other conditions they have are kept. You can take it out again here.\n\n" + list(model.missing))
        }
        .alert("Take the condition out of \(model.covered.count) BetterTouchTool gesture\(model.covered.count == 1 ? "" : "s")?",
               isPresented: $model.confirmRemove) {
            Button("Remove", role: .destructive) { model.removeCondition() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes only the “\(BetterTouchTool.variable) is not 1” condition; any others stay.\n\n" + list(model.covered))
        }
        if model.busy == nil, model.gestures != nil {
            HStack {
                Spacer()
                if !model.covered.isEmpty { Button("Remove condition…") { model.confirmRemove = true } }
                if !model.missing.isEmpty { Button("Add condition to \(model.missing.count)…") { model.confirmAdd = true } }
            }
        }
        if let message = model.message {
            Text(message).font(.callout).foregroundStyle(model.isError ? .red : .secondary)
        }
    }

    private var summary: String {
        guard let g = model.gestures else { return "Not checked" }
        if g.isEmpty { return "None in BTT (\(fingers)-finger swipes)" }
        return "\(model.covered.count) of \(g.count)"
    }

    private func list(_ gestures: [BTTGestureSetup.Gesture]) -> String {
        let lines = gestures.prefix(12).map { "\($0.app) › \($0.name)" }
        let more = gestures.count > 12 ? "\nand \(gestures.count - 12) more" : ""
        return lines.joined(separator: "\n") + more
    }
}
