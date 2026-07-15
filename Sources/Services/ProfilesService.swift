import Foundation
import Supabase

struct ProfileRow: Decodable {
  let id: UUID
  let user_id: UUID
  let display_name: String?
  // Not a DB column -- profiles has no email column at all (email lives on
  // auth.users, which clients can't query directly). Filled in from the
  // already-authenticated session below, not decoded from the row.
  var email: String?

  enum CodingKeys: String, CodingKey {
    case id
    case user_id
    case display_name
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
      .select("id, user_id, display_name")
      .eq("user_id", value: user.id)
      .limit(1)
      .execute()
    var rows = try JSONDecoder().decode([ProfileRow].self, from: res.data)
    guard !rows.isEmpty else { return nil }
    rows[0].email = user.email
    return rows.first
  }
}

