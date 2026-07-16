import Foundation
import Supabase

struct ProfileRow: Decodable {
  let id: UUID
  let user_id: UUID
  let display_name: String?
  let avatar_url: String?
  // Not a DB column -- profiles has no email column at all (email lives on
  // auth.users, which clients can't query directly). Filled in from the
  // already-authenticated session below, not decoded from the row.
  var email: String?

  enum CodingKeys: String, CodingKey {
    case id
    case user_id
    case display_name
    case avatar_url
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
      .select("id, user_id, display_name, avatar_url")
      .eq("user_id", value: user.id)
      .limit(1)
      .execute()
    var rows = try JSONDecoder().decode([ProfileRow].self, from: res.data)
    guard !rows.isEmpty else { return nil }
    rows[0].email = user.email
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

  /// Uploads image data to the public `avatars` bucket under the caller's
  /// own user-id folder (required by that bucket's storage RLS policies)
  /// and returns the public URL to store on profiles.avatar_url.
  func uploadAvatar(data: Data, fileExtension: String) async throws -> String {
    let userId = try await client.auth.session.user.id
    let path = "\(userId)/\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
    try await client.storage.from("avatars").upload(path, data: data, options: FileOptions(upsert: true))
    return try client.storage.from("avatars").getPublicURL(path: path).absoluteString
  }
}

