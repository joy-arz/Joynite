import AppKit
import ImageIO

@MainActor final class ImageRepository {
    static let shared = ImageRepository()
    private let images = NSCache<NSString, NSImage>()
    private var pending: [String: Task<NSImage?, Never>] = [:]
    private init() { images.totalCostLimit = 32 * 1024 * 1024; images.countLimit = 24 }
    func image(at url: URL, maximum: Int) async -> NSImage? {
        let key = url.path + ":" + String(maximum)
        if let image = images.object(forKey: key as NSString) { return image }
        if let task = pending[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximum, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        pending[key] = task
        let image = await task.value
        pending.removeValue(forKey: key)
        if let image { images.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height) * 4) }
        return image
    }
}
