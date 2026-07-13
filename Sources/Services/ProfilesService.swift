import Foundation
import Supabase

struct ProfileRow: Decodable {
  let id: UUID
  let user_id: UUID
  let display_name: String?
  let email: String?

  enum CodingKeys: String, CodingKey {
    case id
    case user_id
    case display_name
    case email
  }
}

struct ProfilesService {
  let client: SupabaseClient

  /// Returns the current user's profile (via view app_profiles or table profiles joined with auth.users).
  func fetchMyProfile() async throws -> ProfileRow? {
    let user = try await client.auth.session.user
    let res = try await client
      .from("app_profiles")
      .select("id, user_id, display_name, email")
      .eq("user_id", value: user.id)
      .limit(1)
      .execute()
    let rows = try JSONDecoder().decode([ProfileRow].self, from: res.data)
    return rows.first
  }
}

