import Foundation
import CryptoKit
import ZIPFoundation

public enum LibraryBackup {
    public struct Manifest: Codable { public let format: Int; public let files: [String: String] }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func valid(_ path: String) -> Bool {
        path == "library.json" || path.range(of: "^Media/[a-f0-9]{64}/[a-f0-9]{64}(\\.fill)?\\.png$", options: .regularExpression) != nil
    }
    public static func export(_ library: LibraryFile, media: URL, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".joynite-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let archive = try Archive(url: temporary, accessMode: .create)
        var hashes: [String: String] = [:]; var total = 0
        func add(_ data: Data, path: String) throws {
            total += data.count
            guard data.count <= 25_000_000, total <= 1_000_000_000, hashes.count < 50_000 else { throw LibraryError.invalid("Backup exceeds the supported size.") }
            hashes[path] = digest(data)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in data.subdata(in: Int(position)..<Int(position) + size) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try add(encoder.encode(library), path: "library.json")
        for game in library.games {
            let folder = media.appendingPathComponent(MediaCache.identifier(game.id))
            if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])) ?? [] {
                let path = "Media/\(folder.lastPathComponent)/\(file.lastPathComponent)"
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard valid(path), values.isRegularFile == true, values.isSymbolicLink != true, hashes[path] == nil else { continue }
                try add(Data(contentsOf: file), path: path)
            }
        }
        let manifest = try encoder.encode(Manifest(format: 1, files: hashes))
        try archive.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(manifest.count), compressionMethod: .deflate) { position, size in manifest.subdata(in: Int(position)..<Int(position) + size) }
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
    public static func restore(_ source: URL, current: LibraryFile, storage: LibraryStorage, media: URL) throws -> LibraryFile {
        let archive = try Archive(url: source, accessMode: .read)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("joynite-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [String: String] = [:]; var manifestData: Data?; var total: UInt64 = 0
        for entry in archive {
            guard entry.type == .file, (valid(entry.path) || entry.path == "manifest.json"), files[entry.path] == nil,
                  entry.path != "manifest.json" || manifestData == nil, entry.uncompressedSize <= 25_000_000, files.count < 50_000 else { throw LibraryError.invalid("Invalid backup entry: \(entry.path)") }
            total += entry.uncompressedSize
            guard total <= 1_000_000_000 else { throw LibraryError.invalid("Backup exceeds the supported size.") }
            var data = Data()
            _ = try archive.extract(entry) { chunk in
                guard data.count + chunk.count <= 25_000_000 else { throw LibraryError.invalid("Backup entry is too large.") }
                data.append(chunk)
            }
            if entry.path == "manifest.json" { manifestData = data; continue }
            files[entry.path] = digest(data)
            let target = staging.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        guard let manifestData else { throw LibraryError.invalid("Backup manifest is missing.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.format == 1, manifest.files == files, files["library.json"] != nil else { throw LibraryError.invalid("Backup integrity verification failed.") }
        let incoming = try LibraryStorage(url: staging.appendingPathComponent("library.json")).load()
        var next = current; var ids = Set(current.games.map(\.id)); var newFolders = Set<String>()
        for game in incoming.games where ids.insert(game.id).inserted { next.games.append(game); newFolders.insert(MediaCache.identifier(game.id)) }
        for folder in incoming.folders where !next.folders.contains(folder) { next.folders.append(folder) }
        var created: [URL] = []
        do {
            for path in files.keys where path.hasPrefix("Media/") && newFolders.contains(path.components(separatedBy: "/")[1]) {
                let relative = String(path.dropFirst(6)); let target = media.appendingPathComponent(relative)
                // Never follow an existing cache directory symlink during restore.
                for url in [media, target.deletingLastPathComponent(), target] {
                    if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw LibraryError.invalid("Restore destination contains a symbolic link.") }
                }
                if FileManager.default.fileExists(atPath: target.path) {
                    guard digest(try Data(contentsOf: target)) == files[path] else { throw LibraryError.invalid("Restore would replace existing artwork.") }; continue
                }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: staging.appendingPathComponent(path), to: target); created.append(target)
            }
            try storage.save(next); return next
        } catch { for url in created { try? FileManager.default.removeItem(at: url) }; throw error }
    }
}
