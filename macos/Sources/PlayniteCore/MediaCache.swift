import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public actor MediaCache {
    public nonisolated let root: URL
    private let session: URLSession
    public init(root: URL, session: URLSession = .shared) { self.root = root; self.session = session }
    public nonisolated static func identifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public nonisolated static func portraitURL(for game: Game) -> String? {
        var id = game.store == .steam ? game.storeID : ""
        if id.isEmpty, let url = URL(string: game.storeURL), url.host == "store.steampowered.com" {
            let components = url.pathComponents
            if let index = components.firstIndex(of: "app"), index + 1 < components.count { id = components[index + 1] }
        }
        guard let number = UInt64(id), number > 0 else { return nil }
        return "https://cdn.akamai.steamstatic.com/steam/apps/\(number)/library_600x900.jpg"
    }
    public nonisolated func directory(for gameID: String) -> URL { root.appendingPathComponent(Self.identifier(gameID), isDirectory: true) }
    public nonisolated func file(gameID: String, key: String?) -> URL? {
        guard let key, key.range(of: "^[a-f0-9]{64}\\.png$", options: .regularExpression) != nil else { return nil }
        let url = directory(for: gameID).appendingPathComponent(key)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    public func cache(_ remote: String, gameID: String) async throws -> String {
        guard let url = URL(string: remote), url.scheme == "https", url.host != nil else { throw LibraryError.invalid("Artwork must use HTTPS.") }
        let key = Self.identifier(remote) + ".png"
        if file(gameID: gameID, key: key) != nil { return key }
        guard ProcessInfo.processInfo.environment["PLAYNITE_OFFLINE"] != "1" else { throw LibraryError.invalid("Offline mode: cached artwork remains available.") }
        var request = URLRequest(url: url); request.timeoutInterval = 18
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), http.url?.scheme == "https" else { throw LibraryError.invalid("Artwork download failed.") }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 24_000_000 else { throw LibraryError.invalid("Artwork exceeds the 24 MB limit.") }
        return try store(Data(contentsOf: temporary), gameID: gameID, key: key)
    }
    @discardableResult public func store(_ data: Data, gameID: String, key: String) throws -> String {
        guard key.range(of: "^[a-f0-9]{64}\\.png$", options: .regularExpression) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1920, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw LibraryError.invalid("Artwork is not a supported image.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw LibraryError.invalid("Cannot encode cached artwork.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.invalid("Cannot finish cached artwork.") }
        let folder = directory(for: gameID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (output as Data).write(to: folder.appendingPathComponent(key), options: .atomic)
        return key
    }
    public func remove(gameID: String) throws {
        let folder = directory(for: gameID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}
