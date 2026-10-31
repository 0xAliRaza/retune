import AppKit
import ImageIO
import LumenCore
import SwiftUI

/// Downloads, downsamples and caches artwork. Posters arrive as full-size TMDB images; decoding them
/// at display size keeps memory flat while scrolling through tens of thousands of titles.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var failed: Set<URL> = []
    private let session: URLSession
    /// Artwork URLs come from the playlist; an endless response must not exhaust memory while scrolling.
    private static let maxArtworkBytes = 32 << 20

    init() {
        memory.countLimit = 600
        // Decoded bitmaps, not files: a 1600 px backdrop is ~5–10 MB in memory.
        memory.totalCostLimit = 300 << 20
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumen/Artwork", isDirectory: true)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 1 << 30, directory: cacheDirectory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: configuration)
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let key = "\(url.absoluteString)#\(Int(maxPixelSize))" as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if failed.contains(url) { return nil }
        if let task = inFlight[key as String] { return await task.value }

        let session = session
        let task = Task<NSImage?, Never>.detached(priority: .utility) {
            guard StreamURLPolicy.isHTTP(url),
                  let (data, response) = try? await session.boundedData(from: url, limit: Self.maxArtworkBytes) else { return nil }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status == 200, let image = Self.downsample(data, maxPixelSize: maxPixelSize) else {
                // Missing or undecodable artwork won't fix itself; timeouts and offline blips might.
                if status == 404 || status == 410 || status == 200 { await self.markFailed(url) }
                return nil
            }
            return image
        }
        inFlight[key as String] = task
        let image = await task.value
        inFlight[key as String] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            memory.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    private func markFailed(_ url: URL) {
        failed.insert(url)
    }

    func clear() {
        memory.removeAllObjects()
        failed = []
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    private static func downsample(_ data: Data, maxPixelSize: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Async artwork with a graceful placeholder.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var maxPixelSize: CGFloat = 400
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var loadedURL: URL?

    var body: some View {
        ZStack {
            if let image, loadedURL == url {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            let result = await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
            withAnimation(.easeOut(duration: 0.2)) {
                image = result
                loadedURL = url
            }
        }
    }
}
