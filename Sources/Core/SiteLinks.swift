import Foundation

/// Every https link the app builds or opens on the website, in one place.
///
/// The apex (stupidunderdogpick.com) has been canonical since Oct 19 2026:
/// www and sup.football 308-redirect to it. Apple won't follow a redirect
/// when it fetches apple-app-site-association, so the apex is the only host
/// whose links can open the app as universal links -- anything the app
/// shares (group invites especially) has to be built on it, not on www.
enum SiteLinks {
  static let baseString = "https://stupidunderdogpick.com"

  /// `path` is a server-relative path like "/groups/join/abc" (what the
  /// groups-create-invite edge function returns as join_url).
  static func url(path: String) -> URL? {
    URL(string: baseString + (path.hasPrefix("/") ? path : "/" + path))
  }

  /// Where the password-reset email lands -- the web's SetNewPassword page,
  /// same redirect the web's own Auth.tsx sends. Must stay in Supabase
  /// Auth's allowed redirect URLs (the apex already is).
  static let setNewPassword = URL(string: baseString + "/set-new-password")!

  // Legal and info pages, opened in a Safari view from Profile. A privacy
  // policy reachable inside the app is App Store guideline 5.1.1(i).
  static let terms = URL(string: baseString + "/terms")!
  static let privacy = URL(string: baseString + "/privacy")!
  static let responsibleGaming = URL(string: baseString + "/responsible-gaming")!
  static let disclosures = URL(string: baseString + "/disclosures")!
  static let about = URL(string: baseString + "/about")!
}
