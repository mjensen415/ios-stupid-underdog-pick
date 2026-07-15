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

  // picks only grants authenticated SELECT -- no INSERT/UPDATE/DELETE.
  // Every write goes through a SECURITY DEFINER RPC instead (same one the
  // web app uses), so business rules like pick-lock enforcement live in
  // one place instead of being duplicated -- and bypassable -- per client.
  // A direct .from("picks").upsert(...)/.delete() here throws "permission
  // denied for table picks" every time.
  @discardableResult
  func upsertPick(gameId: UUID, pickedTeamId: UUID, season: Int, week: Int) async throws -> Pick {
    struct Params: Encodable {
      let p_season: Int
      let p_week: Int
      let p_game_id: UUID
      let p_team_id: UUID
    }
    let res = try await client
      .rpc("upsert_weekly_pick", params: Params(p_season: season, p_week: week, p_game_id: gameId, p_team_id: pickedTeamId))
      .single()
      .execute()
    return try JSONDecoder().decode(Pick.self, from: res.data)
  }

  func clearPick(season: Int, week: Int) async throws {
    struct Params: Encodable {
      let p_season: Int
      let p_week: Int
    }
    _ = try await client
      .rpc("clear_weekly_pick", params: Params(p_season: season, p_week: week))
      .execute()
  }
}
