import Foundation

public enum JoyniteIdentity {
    public static func isLauncher(_ identifier: String) -> Bool {
        let id = identifier.lowercased()
        return id.hasPrefix("io.github.joy-arz.joynite") || id.hasPrefix("io.github.joy-arz.playnite")
    }
}
public enum LibraryMigration {
    public static func prepare(destination: URL, legacyDirectories: [URL], fileManager: FileManager = .default) throws {
        guard !fileManager.fileExists(atPath: destination.path),
              let source = legacyDirectories.first(where: { fileManager.fileExists(atPath: $0.appendingPathComponent("library.json").path) }) else { return }
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".joynite-migration-" + UUID().uuidString)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: source, to: staging)
        try fileManager.moveItem(at: staging, to: destination)
    }
}
