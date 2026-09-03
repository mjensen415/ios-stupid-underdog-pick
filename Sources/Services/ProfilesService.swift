import Foundation
import Supabase

struct ProfileRow: Decodable {
  let id: UUID
  let user_id: UUID
  let display_name: String?
  let avatar_url: String?
  let has_onboarded: Bool
  let favorite_team_id: UUID?
  let game_interests: [String]
  let pickems_intro_dismissed: Bool
  // Not a DB column -- profiles has no email column at all (email lives on
  // auth.users, which clients can't query directly). Filled in from the
  // already-authenticated session below, not decoded from the row.
  var email: String?

  enum CodingKeys: String, CodingKey {
    case id
    case user_id
    case display_name
    case avatar_url
    case has_onboarded
    case favorite_team_id
    case game_interests
    case pickems_intro_dismissed
  }
}

struct ProfilesService {
  let client: SupabaseClient

  /// Returns the current user's profile. Was querying a table named
  /// "app_profiles" that doesn't exist anywhere in the schema -- every call
  /// threw, and the caller's catch-and-ignore left the Profile screen
  /// showing a spinner forever. The real table is "profiles", keyed by
  /// user_id (not id, which is an unrelated auto-generated PK -- the same
  /// mixup that broke new-user signup earlier).
  func fetchMyProfile() async throws -> ProfileRow? {
    let user = try await client.auth.session.user
    let res = try await client
      .from("profiles")
      .select("id, user_id, display_name, avatar_url, has_onboarded, favorite_team_id, game_interests, pickems_intro_dismissed")
      .eq("user_id", value: user.id)
      .limit(1)
      .execute()
    var rows = try JSONDecoder().decode([ProfileRow].self, from: res.data)
    guard !rows.isEmpty else { return nil }
    rows[0].email = user.email
    return rows.first
  }

  /// Another user's profile for the public profile screen -- profiles RLS
  /// (profiles_read_names: true) already makes every row name/avatar
  /// readable regardless of is_public, so this is a plain lookup by id,
  /// not gated the way fetchMyProfile's own-session read is. No email:
  /// that's session-only, never exposed for someone else's account.
  func fetchProfile(userId: UUID) async throws -> ProfileRow? {
    let res = try await client
      .from("profiles")
      .select("id, user_id, display_name, avatar_url, has_onboarded, favorite_team_id, game_interests, pickems_intro_dismissed")
      .eq("user_id", value: userId)
      .limit(1)
      .execute()
    let rows = try JSONDecoder().decode([ProfileRow].self, from: res.data)
    return rows.first
  }

  /// profiles previously granted `authenticated` SELECT only -- this update
  /// threw "permission denied for table profiles" for every caller, even
  /// though the RLS policy scoping it to the caller's own row was already
  /// correct. Fixed server-side with a scoped GRANT UPDATE; this client
  /// code was already doing the right thing, it just couldn't get through.
  func updateProfile(displayName: String? = nil, avatarUrl: String? = nil) async throws {
    struct Update: Encodable {
      let display_name: String?
      let avatar_url: String?
    }
    let userId = try await client.auth.session.user.id
    _ = try await client
      .from("profiles")
      .update(Update(display_name: displayName, avatar_url: avatarUrl))
      .eq("user_id", value: userId)
      .execute()
  }

  /// Sets the user's optional favorite team, independent of onboarding
  /// completion -- called as soon as a team is tapped in the onboarding
  /// flow, not deferred to the end, so a partial run still saves it.
  func setFavoriteTeam(_ teamId: UUID) async throws {
    struct Update: Encodable { let favorite_team_id: UUID }
    let userId = try await client.auth.session.user.id
    _ = try await client
      .from("profiles")
      .update(Update(favorite_team_id: teamId))
      .eq("user_id", value: userId)
      .execute()
  }

  /// Marks the one-time first-run flow (what do you play? -> team -> first
  /// pick -> group) done, whether completed or explicitly skipped --
  /// RootView never shows it again once this is true. Also records the
  /// step-one game selections and marks the legacy Pickems re-intro banner
  /// moot, since onboarding just asked directly -- no need to also nag on
  /// Home.
  func completeOnboarding(gameInterests: [String]) async throws {
    struct Update: Encodable { let has_onboarded: Bool; let game_interests: [String]; let pickems_intro_dismissed: Bool }
    let userId = try await client.auth.session.user.id
    _ = try await client
      .from("profiles")
      .update(Update(has_onboarded: true, game_interests: gameInterests, pickems_intro_dismissed: true))
      .eq("user_id", value: userId)
      .execute()
  }

  /// Dismisses the one-time Home banner shown to accounts that onboarded
  /// before Pickems existed (has_onboarded was already true, so the new
  /// onboarding step never ran for them).
  func dismissPickemsIntro() async throws {
    struct Update: Encodable { let pickems_intro_dismissed: Bool }
    let userId = try await client.auth.session.user.id
    _ = try await client
      .from("profiles")
      .update(Update(pickems_intro_dismissed: true))
      .eq("user_id", value: userId)
      .execute()
  }

  /// Uploads image data to the public `avatars` bucket under the caller's
  /// own user-id folder (required by that bucket's storage RLS policies)
  /// and returns the public URL to store on profiles.avatar_url.
  func uploadAvatar(data: Data, fileExtension: String) async throws -> String {
    let userId = try await client.auth.session.user.id
    let path = "\(userId)/\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
    try await client.storage.from("avatars").upload(path, data: data, options: FileOptions(upsert: true))
    return try client.storage.from("avatars").getPublicURL(path: path).absoluteString
  }

  /// Self-service account deletion (Apple Guideline 5.1.1(v)). Calls the
  /// delete-account edge function, which authenticates the caller from
  /// their own JWT (never a client-supplied id), cleans up profile/group
  /// membership rows, and deletes the auth.users row via the Admin API.
  /// Mirrors GroupsService.invoke's error-unwrapping pattern -- the function
  /// returns non-2xx (401/409/500) with a JSON {success:false, error} body
  /// for expected failures (not signed in, owns a group with other members,
  /// etc.), which surfaces as FunctionsError.httpError rather than a
  /// decoded response.
  struct DeleteAccountError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  private struct DeleteAccountResponse: Decodable { let success: Bool }
  private struct DeleteAccountErrorBody: Decodable { let success: Bool; let error: String? }

  func deleteAccount() async throws {
    do {
      let _: DeleteAccountResponse = try await client.functions.invoke("delete-account", options: .init(method: .post))
    } catch let FunctionsError.httpError(_, data) {
      if let body = try? JSONDecoder().decode(DeleteAccountErrorBody.self, from: data), let message = body.error {
        throw DeleteAccountError(message: message)
      }
      throw DeleteAccountError(message: "Couldn't delete account. Try again.")
    }
  }
}

