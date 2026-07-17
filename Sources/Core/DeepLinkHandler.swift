import Foundation
import Supabase

// Single entry point for every incoming URL: the sup://underdog custom
// scheme (magic-link/OAuth callback) and https://www.stupidunderdogpick.com/...
// universal links (group invites) -- sup.football and the bare
// stupidunderdogpick.com both redirect at the Vercel domain level, which
// breaks Apple's no-redirect apple-app-site-association fetch requirement,
// so www.stupidunderdogpick.com is the only domain actually registered.
// Both StupidUnderdogApp.onOpenURL and any future universal-link entry
// point should delegate here rather than re-implementing routing inline.
@MainActor
struct DeepLinkHandler {
  let client: SupabaseClient
  let appState: AppState

  func handle(url: URL) async {
    #if DEBUG
    print("[DeepLink] received URL:", url.absoluteString)
    #endif

    if let token = groupJoinToken(from: url) {
      appState.pendingGroupJoinToken = token
      return
    }

    // Otherwise, assume it's an auth callback (magic link / OAuth), the
    // only other kind of URL this app currently registers for.
    do {
      try await client.auth.session(from: url)
      let session = try? await client.auth.session
      appState.session = session
      #if DEBUG
      print("[DeepLink] session restored via URL:", url.absoluteString)
      #endif
    } catch {
      #if DEBUG
      print("[DeepLink][ERR]", error.localizedDescription)
      #endif
    }
  }

  /// Matches "/groups/join/{token}" on either a universal-link https URL
  /// or a sup://underdog/groups/join/{token} custom-scheme fallback.
  private func groupJoinToken(from url: URL) -> String? {
    let parts = url.pathComponents.filter { $0 != "/" }
    guard let joinIndex = parts.firstIndex(of: "join"),
          parts[safe: joinIndex - 1] == "groups",
          let token = parts[safe: joinIndex + 1],
          !token.isEmpty
    else { return nil }
    return token
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
