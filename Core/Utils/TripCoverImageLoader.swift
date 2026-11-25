import UIKit

/// Process-lifetime image cache for trip covers and shared remote photos.
/// Avoids layout flash when the same URL reappears in lists / hero cards.
enum TracciImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: max(cost, 1))
    }

    static func remove(for url: URL) {
        cache.removeObject(forKey: url.absoluteString as NSString)
    }
}

enum TripCoverImageLoader {
    static let defaultTimeout: TimeInterval = 12

    static func load(url: URL, timeout: TimeInterval = defaultTimeout) async -> UIImage? {
        if let cached = TracciImageCache.image(for: url) {
            return cached
        }

        let image = await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await fetch(url: url, timeout: timeout)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        if let image {
            TracciImageCache.store(image, for: url)
        }
        return image
    }

    private static func fetch(url: URL, timeout: TimeInterval) async -> UIImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
