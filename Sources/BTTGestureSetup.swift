import Foundation

/// One-time helper for the BetterTouchTool option: adds the condition `swipeswitch_active != "1"` to BTT's swipe
/// gestures (the ones SwipeSwitch also uses), so BTT skips them while the switcher is open, and can take it out again.
///
/// It uses BTT's documented scripting commands (`get_triggers`, `get_trigger`, `update_trigger`). The condition itself
/// travels in a trigger field whose format BTT doesn't document, so every step checks what it reads and writes:
/// if anything looks different from what we expect (say, after a BTT update), it stops and changes nothing more,
/// and the manual steps in the README still work.
enum BTTGestureSetup {
    struct Gesture {
        let uuid: String
        let name: String          // "3 Finger Swipe Up"
        let app: String           // "For All Apps" or the app's name
        let conditions: NSPredicate?
        var hasOurCondition: Bool { conditions.map(BTTGestureSetup.contains) ?? false }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static var ours: NSPredicate { NSPredicate(format: "\(BetterTouchTool.variable) != %@", "1") }

    // MARK: Scan

    /// Every trackpad swipe gesture in BTT for the given finger count, with its current conditions.
    static func scan(fingers: Int) throws -> [Gesture] {
        let reply = try send("Gets", params: ["btTt": "BTTTriggerTypeTouchpadAll"])
        guard let start = reply.firstIndex(of: "["),
              let list = try? JSONSerialization.jsonObject(with: Data(reply[start...].utf8)) as? [[String: Any]] else {
            throw Failure(description: "BetterTouchTool's list of gestures wasn't in the expected format.")
        }
        var result: [Gesture] = []
        for t in list where (t["BTTIsPureAction"] as? Bool) != true {
            guard let type = t["BTTTriggerType"] as? Int,
                  let name = swipeName(type: type, description: t["BTTTriggerTypeDescriptionReadOnly"] as? String, fingers: fingers),
                  let uuid = t["BTTUUID"] as? String else { continue }
            let app = (t["BTTBelongsToApp"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "For All Apps"
            result.append(Gesture(uuid: uuid, name: name, app: app, conditions: try conditions(of: t)))
        }
        return result.sorted { ($0.app, $0.name) < ($1.app, $1.name) }
    }

    /// BTT's numbers for the three-finger swipes (it doesn't name them in the trigger list for every app); other finger
    /// counts are recognized by name.
    private static let threeFingerSwipes = [100: "Left", 101: "Right", 102: "Up", 103: "Down"]

    private static func swipeName(type: Int, description: String?, fingers: Int) -> String? {
        if fingers == 3, let dir = threeFingerSwipes[type] { return "3 Finger Swipe \(dir)" }
        guard let description else { return nil }
        for dir in ["Left", "Right", "Up", "Down"] where description == "\(fingers) Finger Swipe \(dir)" { return description }
        return nil
    }

    // MARK: Add / remove

    /// Adds the condition to each gesture that doesn't have it. Stops at the first gesture that doesn't read back as
    /// expected (that one is put back as it was). Returns how many were changed. `progress` is called after each one.
    @discardableResult
    static func add(to gestures: [Gesture], progress: (Int) -> Void = { _ in }) throws -> Int {
        var done = 0
        for g in gestures where !g.hasOurCondition {
            try write(g, combined(g.conditions)) { after in
                guard let after, contains(after) else { return false }
                return g.conditions.map { keepsAll($0, in: after) } ?? true
            }
            done += 1
            progress(done)
        }
        return done
    }

    /// Takes the condition out of each gesture that has it, leaving any other conditions as they were.
    @discardableResult
    static func remove(from gestures: [Gesture], progress: (Int) -> Void = { _ in }) throws -> Int {
        var done = 0
        for g in gestures where g.hasOurCondition {
            let rest = stripped(g.conditions)
            try write(g, rest) { after in rest == nil ? after == nil : (after.map { !contains($0) } ?? false) }
            done += 1
            progress(done)
        }
        return done
    }

    /// Writes new conditions, reads the gesture back and checks it with `expect`. If the check fails, writes the old
    /// conditions back and throws.
    private static func write(_ g: Gesture, _ new: NSPredicate?, expect: (NSPredicate?) -> Bool) throws {
        try update(g.uuid, new)
        let after = try readConditions(g.uuid)
        guard expect(after) else {
            try? update(g.uuid, g.conditions)
            throw Failure(description: "BetterTouchTool didn't keep the change to “\(g.name)” (\(g.app)). This BTT version may store conditions differently; add the condition by hand as described in the README.")
        }
    }

    private static func update(_ uuid: String, _ predicate: NSPredicate?) throws {
        // No conditions is sent as an empty string (BTT ignores null here); BTT then reports the gesture as having none.
        let value = try predicate.map { try encode($0) } ?? ""
        let json = try JSONSerialization.data(withJSONObject: ["BTTTriggerConditionsData": value])
        _ = try send("Updt", direct: uuid, params: ["btJS": String(decoding: json, as: UTF8.self)])
    }

    private static func readConditions(_ uuid: String) throws -> NSPredicate? {
        let reply = try send("Geti", direct: uuid)
        guard let start = reply.firstIndex(of: "{"),
              let t = try? JSONSerialization.jsonObject(with: Data(reply[start...].utf8)) as? [String: Any] else {
            throw Failure(description: "BetterTouchTool's description of a gesture wasn't in the expected format.")
        }
        return try conditions(of: t)
    }

    // MARK: Conditions

    /// Reads a trigger's conditions. BTT sends them as a base64 keyed archive of an NSPredicate, with "_" for "/".
    private static func conditions(of t: [String: Any]) throws -> NSPredicate? {
        let text = (t["BTTTriggerConditionsFormatReadOnly"] as? String) ?? ""
        guard let encoded = t["BTTTriggerConditionsData"] as? String, !encoded.isEmpty else {
            if text.isEmpty { return nil }
            throw Failure(description: "BetterTouchTool reported conditions in a format SwipeSwitch doesn't recognize.")
        }
        guard let data = Data(base64Encoded: encoded.replacingOccurrences(of: "_", with: "/")),
              let p = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: archiveClasses, from: data) as? NSPredicate else {
            throw Failure(description: "BetterTouchTool reported conditions in a format SwipeSwitch doesn't recognize.")
        }
        return p
    }

    private static let archiveClasses: [AnyClass] = [NSPredicate.self, NSCompoundPredicate.self, NSComparisonPredicate.self,
                                                     NSExpression.self, NSArray.self, NSString.self, NSNumber.self]

    private static func encode(_ p: NSPredicate) throws -> String {
        let data = try NSKeyedArchiver.archivedData(withRootObject: p, requiringSecureCoding: false)
        return data.base64EncodedString().replacingOccurrences(of: "/", with: "_")
    }

    /// Our condition alongside the existing ones (all must hold), the way BTT's condition editor stores them.
    private static func combined(_ existing: NSPredicate?) -> NSPredicate {
        guard let existing else { return NSCompoundPredicate(andPredicateWithSubpredicates: [ours]) }
        if let c = existing as? NSCompoundPredicate, c.compoundPredicateType == .and, let subs = c.subpredicates as? [NSPredicate] {
            return NSCompoundPredicate(andPredicateWithSubpredicates: subs + [ours])
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [existing, ours])
    }

    /// The conditions without ours; nil when nothing else is left.
    private static func stripped(_ existing: NSPredicate?) -> NSPredicate? {
        guard let existing, existing != ours else { return nil }
        guard let c = existing as? NSCompoundPredicate, c.compoundPredicateType == .and,
              let subs = c.subpredicates as? [NSPredicate] else { return existing }
        let rest = subs.filter { $0 != ours }
        return rest.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: rest)
    }

    private static func contains(_ p: NSPredicate) -> Bool {
        if p == ours { return true }
        guard let c = p as? NSCompoundPredicate, c.compoundPredicateType == .and,
              let subs = c.subpredicates as? [NSPredicate] else { return false }
        return subs.contains(ours)
    }

    /// True if every condition in `old` is still part of `new`.
    private static func keepsAll(_ old: NSPredicate, in new: NSPredicate) -> Bool {
        guard let n = new as? NSCompoundPredicate, let newSubs = n.subpredicates as? [NSPredicate] else { return false }
        if let o = old as? NSCompoundPredicate, o.compoundPredicateType == .and, let oldSubs = o.subpredicates as? [NSPredicate] {
            return oldSubs.allSatisfy(newSubs.contains)
        }
        return newSubs.contains(old)
    }

    private static func send(_ id: String, direct: String? = nil, params: [String: String] = [:]) throws -> String {
        do { return try BetterTouchTool.command(id, direct: direct, params: params) }
        catch { throw Failure(description: "Couldn't reach BetterTouchTool (\(error.localizedDescription)). Check that it's running and that SwipeSwitch may control it (System Settings › Privacy & Security › Automation).") }
    }
}
