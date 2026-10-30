import Foundation

public struct LaunchReport: Codable, Sendable {
    public let state: String
    public let detail: String
    public let timestamp: Date
    public let processID: Int32?
    public let exitCode: Int32?
    public let elapsedSeconds: Double?
    public init(state: String, detail: String, processID: Int32? = nil, exitCode: Int32? = nil, elapsedSeconds: Double? = nil) {
        self.state = state; self.detail = detail; timestamp = Date(); self.processID = processID; self.exitCode = exitCode; self.elapsedSeconds = elapsedSeconds
    }
}
public enum LaunchDiagnostics {
    public static func file(root: URL, gameID: String) -> URL { root.appendingPathComponent("Logs").appendingPathComponent(MediaCache.identifier(gameID) + ".launch.json") }
    public static func write(_ report: LaunchReport, root: URL, gameID: String) throws {
        let url = file(root: root, gameID: gameID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(report).write(to: url, options: .atomic)
    }
    public static func read(root: URL, gameID: String) -> LaunchReport? {
        let url = file(root: root, gameID: gameID)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LaunchReport.self, from: data)
    }
}
