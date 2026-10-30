import SwiftUI
import ImageIO

/// Drop-in-ish replacement for AsyncImage that survives the same
/// intermittent connection resets NetworkRetryURLProtocol already fixed for
/// the Supabase client -- plain AsyncImage uses its own default URLSession
/// with no retry, so a team logo whose URL is completely valid (confirmed:
/// UCLA and Cal Golden Bears both return 200 with real image bytes via
/// curl) can still render as a blank placeholder forever if that one load
/// attempt happens to hit a reset. Team logos rarely change, so normal HTTP
/// caching stays on here (unlike the Supabase API session) -- only the
/// retry behavior is added.
enum RetryingImageLoading {
  static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.protocolClasses = [NetworkRetryURLProtocol.self] + (config.protocolClasses ?? [])
    return URLSession(configuration: config)
  }()
}

/// Decoded logos, shared by every row. Logos are 500x500 PNGs; decoding
/// them full size on the main thread for every row (and again each time a
/// row scrolled back into view) made the 50+ game CFB list slow to open
/// and stutter on scroll. Images are downsampled off the main thread once,
/// kept in memory, and concurrent requests for the same URL share one load.
actor LogoStore {
  static let shared = LogoStore()
  /// Pixel cap: the largest logo on screen is ~72pt (216px at 3x).
  static let maxPixel = 240

  nonisolated private let cache = NSCache<NSURL, UIImage>()
  private var inFlight: [URL: Task<UIImage?, Never>] = [:]

  nonisolated func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

  func image(for url: URL) async -> UIImage? {
    if let img = cached(url) { return img }
    if let t = inFlight[url] { return await t.value }
    let t = Task.detached(priority: .userInitiated) { () -> UIImage? in
      guard let (data, _) = try? await RetryingImageLoading.session.data(from: url) else { return nil }
      return Self.downsample(data)
    }
    inFlight[url] = t
    let img = await t.value
    inFlight[url] = nil
    if let img { cache.setObject(img, forKey: url as NSURL) }
    return img
  }

  private static func downsample(_ data: Data) -> UIImage? {
    let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    if let src, let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
      return UIImage(cgImage: cg)
    }
    return UIImage(data: data)
  }
}

struct RetryingAsyncImage<Content: View, Placeholder: View>: View {
  let url: URL?
  @ViewBuilder var content: (Image) -> Content
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var uiImage: UIImage?

  var body: some View {
    // A cached logo draws on the first frame, so rows scrolling back in
    // don't flash the placeholder.
    let shown = uiImage ?? url.flatMap { LogoStore.shared.cached($0) }
    Group {
      if let shown {
        content(Image(uiImage: shown))
      } else {
        placeholder()
      }
    }
    .task(id: url) {
      guard let url else { uiImage = nil; return }
      if let hit = LogoStore.shared.cached(url) { uiImage = hit; return }
      uiImage = nil
      uiImage = await LogoStore.shared.image(for: url)
    }
  }
}
