import XCTest
import Auth
@testable import Stupid_Underdog_Pick

/// Offline checks for the phase-1 account/link logic -- no Supabase needed.
final class AccountLinksTests: XCTestCase {

  // User decoded from GoTrue-shaped JSON with the SDK's own decoder, so the
  // test exercises the same field mapping a real session would.
  private func user(appProvider: String, identities: [(String, String?)]) throws -> User {
    let ids = identities.map { provider, lastSignIn in
      """
      {"id":"\(UUID().uuidString)","identity_id":"\(UUID().uuidString)","user_id":"00000000-0000-0000-0000-000000000001",
       "provider":"\(provider)"\(lastSignIn.map { ",\"last_sign_in_at\":\"\($0)\"" } ?? "")}
      """
    }.joined(separator: ",")
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001","aud":"authenticated",
     "app_metadata":{"provider":"\(appProvider)"},"user_metadata":{},
     "created_at":"2025-01-01T00:00:00Z","updated_at":"2026-10-20T00:00:00Z",
     "is_anonymous":false,"identities":[\(ids)]}
    """
    return try AuthClient.Configuration.jsonDecoder.decode(User.self, from: Data(json.utf8))
  }

  func testLastLoginUsesNewestIdentityNotSignupProvider() throws {
    // Signed up with email, most recently came back through Google.
    let u = try user(appProvider: "email", identities: [
      ("email", "2026-09-01T12:00:00Z"),
      ("google", "2026-10-19T08:30:00Z"),
    ])
    XCTAssertEqual(LastLoginStore.method(from: u), .google)
  }

  func testLastLoginFallsBackToAppMetadataProvider() throws {
    let u = try user(appProvider: "apple", identities: [])
    XCTAssertEqual(LastLoginStore.method(from: u), .apple)
  }

  func testLastLoginIgnoresUnknownProviders() throws {
    let u = try user(appProvider: "github", identities: [("github", "2026-10-19T08:30:00Z")])
    XCTAssertNil(LastLoginStore.method(from: u))
  }

  func testInviteLinksAreBuiltOnTheApex() {
    XCTAssertEqual(
      SiteLinks.url(path: "/groups/join/abc123")?.absoluteString,
      "https://stupidunderdogpick.com/groups/join/abc123"
    )
  }

  @MainActor
  func testInviteTokenParsesFromAnyHost() {
    for host in ["stupidunderdogpick.com", "www.stupidunderdogpick.com"] {
      let url = URL(string: "https://\(host)/groups/join/tok_42")!
      XCTAssertEqual(DeepLinkHandler.groupJoinToken(from: url), "tok_42", host)
    }
    XCTAssertEqual(DeepLinkHandler.groupJoinToken(from: URL(string: "sup://underdog/groups/join/tok_42")!), "tok_42")
    XCTAssertNil(DeepLinkHandler.groupJoinToken(from: URL(string: "https://stupidunderdogpick.com/games")!))
  }
}
