import Foundation
import Supabase

struct Profile: Codable, Equatable {
  let id: UUID
  let email: String
  let display_name: String?
}

struct ProfilesRepository {
  let client: SupabaseClient

  func me() async throws -> Profile {
    let authUser = try await client.auth.session.user
    let rows: [Profile] = try await client
      .from("profiles")
      .select("id, email, display_name")
      .eq("id", value: authUser.id)
      .limit(1)
      .execute()
      .value
    if let profile = rows.first { return profile }
    // Fallback with auth data if profile row doesn't exist yet
    return Profile(id: authUser.id, email: authUser.email ?? "", display_name: nil)
  }

  func updateDisplayName(_ name: String) async throws {
    struct Update: Encodable { let display_name: String }
    let authUser = try await client.auth.session.user
    _ = try await client
      .from("profiles")
      .update(Update(display_name: name))
      .eq("id", value: authUser.id)
      .execute()
  }
}

