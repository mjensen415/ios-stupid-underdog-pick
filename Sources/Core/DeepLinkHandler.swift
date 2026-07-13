import Foundation
import Supabase

@MainActor
struct DeepLinkHandler {
  let client: SupabaseClient
  let appState: AppState

  /// Handle sup://underdog magic link / OAuth callback
  func handle(url: URL) async {
    do {
      try await client.auth.session(from: url)
      // Update global session after exchange
      let session = try? await client.auth.session
      appState.session = session
      #if DEBUG
      print("[DeepLink] Session restored via URL:", url.absoluteString)
      #endif
    } catch {
      #if DEBUG
      print("[DeepLink][ERR]", error.localizedDescription)
      #endif
    }
  }
}
