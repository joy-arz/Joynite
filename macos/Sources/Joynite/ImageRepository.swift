import AppKit
import ImageIO
import CoreImage

@MainActor final class ImageRepository {
    static let shared = ImageRepository()
    private let images = NSCache<NSString, NSImage>()
    private var pending: [String: Task<NSImage?, Never>] = [:]
    private init() { images.totalCostLimit = 32 * 1024 * 1024; images.countLimit = 24 }
    func image(at url: URL, maximum: Int, softened: Bool = false) async -> NSImage? {
        let key = url.path + ":" + String(maximum) + (softened ? ":soft" : "")
        if let image = images.object(forKey: key as NSString) { return image }
        if let task = pending[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 32_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximum, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            let output: CGImage
            if softened {
                let input = CIImage(cgImage: image)
                let filtered = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5]).cropped(to: input.extent)
                output = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(filtered, from: input.extent) ?? image
            } else { output = image }
            return NSImage(cgImage: output, size: NSSize(width: image.width, height: image.height))
        }
        pending[key] = task
        let image = await task.value
        pending.removeValue(forKey: key)
        if let image { images.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height) * 4) }
        return image
    }
}
