import SwiftUI

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

struct RetryingAsyncImage<Content: View, Placeholder: View>: View {
  let url: URL?
  @ViewBuilder var content: (Image) -> Content
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var uiImage: UIImage?

  var body: some View {
    Group {
      if let uiImage {
        content(Image(uiImage: uiImage))
      } else {
        placeholder()
      }
    }
    .task(id: url) {
      uiImage = nil
      guard let url else { return }
      guard let (data, _) = try? await RetryingImageLoading.session.data(from: url) else { return }
      uiImage = UIImage(data: data)
    }
  }
}
