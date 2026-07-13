import Foundation
import Supabase

struct Team: Decodable, Identifiable {
  let id: UUID
  let logo_url: String?
  let school_name: String?
  let name: String?
}

struct TeamService {
  let client: SupabaseClient

  func fetchAll() async throws -> [Team] {
    let res = try await client.database
      .from("teams")
      .select("id, logo_url, school_name, name")
      .execute()
    return try JSONDecoder().decode([Team].self, from: res.data)
  }
}


