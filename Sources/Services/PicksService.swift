import Foundation
import Supabase
// Uses canonical Pick model from Sources/Data/Models/Pick.swift

struct PicksService {
  let client: SupabaseClient

  func myPick(season: Int, week: Int) async throws -> Pick? {
    let userId = try await client.auth.session.user.id
    let res = try await client
      .from("picks")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .eq("user_id", value: userId)
      .eq("season", value: season)
      .eq("week", value: week)
      .execute()
    return try JSONDecoder().decode([Pick].self, from: res.data).first
  }

  @discardableResult
  func upsertPick(gameId: UUID, pickedTeamId: UUID, season: Int, week: Int) async throws -> Pick {
    let userId = try await client.auth.session.user.id
    struct PickUpsertPayload: Encodable {
      let user_id: UUID
      let game_id: UUID
      let picked_team_id: UUID
      let season: Int
      let week: Int
    }
    let payload = PickUpsertPayload(
      user_id: userId,
      game_id: gameId,
      picked_team_id: pickedTeamId,
      season: season,
      week: week
    ) // upsert on (user_id,season,week)
    let res = try await client
      .from("picks")
      .upsert(payload, onConflict: "user_id,season,week")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .single()
      .execute()
    return try JSONDecoder().decode(Pick.self, from: res.data)
  }

  func clearPick(season: Int, week: Int) async throws {
    let userId = try await client.auth.session.user.id
    _ = try await client
      .from("picks")
      .delete()
      .eq("user_id", value: userId)
      .eq("season", value: season)
      .eq("week", value: week)
      .execute()
  }
}
