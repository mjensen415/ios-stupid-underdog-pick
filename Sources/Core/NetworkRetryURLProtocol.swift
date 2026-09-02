import Foundation

/// Transparently retries a request that fails with a transient connection
/// error -- confirmed via live traffic that some networks intermittently
/// reset the QUIC (HTTP/3) connection URLSession opens by default
/// (NSURLErrorNetworkConnectionLost, -1005), even though the connection
/// succeeds most of the time on the same network. Disabling HTTP/3 has no
/// public API on iOS (the only known technique is an undocumented KVC key,
/// which turned out not to be recognized on this SDK anyway -- traffic kept
/// opening as QUIC regardless). A retry is the fully-public-API fix: since
/// the failure is intermittent rather than a hard block, the immediate
/// retry very likely succeeds. Registered on the Supabase client's
/// URLSessionConfiguration in SupabaseClientProvider.
final class NetworkRetryURLProtocol: URLProtocol {
  private static let maxAttempts = 3
  private static let retryableCodes: Set<Int> = [
    NSURLErrorNetworkConnectionLost,
    NSURLErrorTimedOut,
  ]

  private var activeTask: URLSessionDataTask?
  private var attempt = 1

  // Only claim requests once -- canInit is also asked about the internal
  // request this protocol issues on its own private session, but that
  // session has no protocolClasses registered, so it never re-enters here.
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.scheme == "https" || request.url?.scheme == "http"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    perform()
  }

  override func stopLoading() {
    activeTask?.cancel()
    activeTask = nil
  }

  private func perform() {
    // A plain, unregistered session -- avoids this protocol intercepting
    // its own retry attempts.
    let session = URLSession(configuration: .ephemeral)
    activeTask = session.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      if let error = error as NSError?,
         error.domain == NSURLErrorDomain,
         Self.retryableCodes.contains(error.code),
         self.attempt < Self.maxAttempts {
        self.attempt += 1
        // Brief backoff -- the earlier failure was mid-handshake, so an
        // instant retry can race the same bad path again.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
          self?.perform()
        }
        return
      }

      if let response {
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      }
      if let data {
        self.client?.urlProtocol(self, didLoad: data)
      }
      if let error {
        self.client?.urlProtocol(self, didFailWithError: error)
      } else {
        self.client?.urlProtocolDidFinishLoading(self)
      }
    }
    activeTask?.resume()
  }
}
