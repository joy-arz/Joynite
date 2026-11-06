import Foundation

public struct LaunchGate {
    private var pending: Set<String> = []
    private var accepted: [String: Date] = [:]
    public init() {}
    public mutating func begin(_ id: String, now: Date = Date()) -> Bool {
        accepted = accepted.filter { now.timeIntervalSince($0.value) < 2 }
        guard !pending.contains(id), accepted[id] == nil else { return false }
        pending.insert(id)
        return true
    }
    public mutating func finish(_ id: String, accepted success: Bool, now: Date = Date()) {
        pending.remove(id)
        if success { accepted[id] = now } else { accepted.removeValue(forKey: id) }
    }
}
