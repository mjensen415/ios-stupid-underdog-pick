import Foundation
import Supabase
// Uses canonical Pick model from Sources/Data/Models/Pick.swift

struct CopyPickResult: Decodable {
  let copied: Bool
  let reason: String?
}

struct PicksService {
  let client: SupabaseClient

  // Effective pick = groupId's own scoped pick if it has one, else the
  // shared (group_id IS NULL) pick -- same fallback the backend uses
  // when scoring, mirrored here so what's shown always matches what
  // counts. groupId nil (the default, every existing call site) reads
  // only the shared pick, unchanged from before group-scoping existed.
  func myPick(season: Int, week: Int, sport: String = "cfb", groupId: UUID? = nil) async throws -> Pick? {
    let userId = try await client.auth.session.user.id
    let sharedRes = try await client
      .from("picks")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .eq("user_id", value: userId)
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
      .is("group_id", value: nil)
      .execute()
    let shared = try JSONDecoder().decode([Pick].self, from: sharedRes.data).first
    guard let groupId else { return shared }

    let groupRes = try await client
      .from("picks")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .eq("user_id", value: userId)
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
      .eq("group_id", value: groupId)
      .execute()
    let groupPick = try JSONDecoder().decode([Pick].self, from: groupRes.data).first
    return groupPick ?? shared
  }

  /// All of the caller's picks, optionally scoped to one season (pass nil
  /// for full cross-season history). Mirrors myPick's query shape, just
  /// without the season/week filters.
  func myPicks(season: Int? = nil) async throws -> [Pick] {
    let userId = try await client.auth.session.user.id
    var query = client
      .from("picks")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .eq("user_id", value: userId)
    if let season {
      query = query.eq("season", value: season)
    }
    let res = try await query
      .order("season", ascending: false)
      .order("week", ascending: false)
      .execute()
    return try JSONDecoder().decode([Pick].self, from: res.data)
  }

  // picks only grants authenticated SELECT -- no INSERT/UPDATE/DELETE.
  // Every write goes through a SECURITY DEFINER RPC instead (same one the
  // web app uses), so business rules like pick-lock enforcement live in
  // one place instead of being duplicated -- and bypassable -- per client.
  // A direct .from("picks").upsert(...)/.delete() here throws "permission
  // denied for table picks" every time.
  @discardableResult
  func upsertPick(gameId: UUID, pickedTeamId: UUID, season: Int, week: Int, groupId: UUID? = nil) async throws -> Pick {
    struct Params: Encodable {
      let p_season: Int
      let p_week: Int
      let p_game_id: UUID
      let p_team_id: UUID
      let p_group_id: UUID?
    }
    let res = try await client
      .rpc("upsert_weekly_pick", params: Params(p_season: season, p_week: week, p_game_id: gameId, p_team_id: pickedTeamId, p_group_id: groupId))
      .single()
      .execute()
    return try JSONDecoder().decode(Pick.self, from: res.data)
  }

  func clearPick(season: Int, week: Int, sport: String = "cfb", groupId: UUID? = nil) async throws {
    struct Params: Encodable {
      let p_season: Int
      let p_week: Int
      let p_sport: String
      let p_group_id: UUID?
    }
    _ = try await client
      .rpc("clear_weekly_pick", params: Params(p_season: season, p_week: week, p_sport: sport, p_group_id: groupId))
      .execute()
  }

  // Deletes this group's own scoped pick for the week, reverting the
  // pick screen back to showing the shared/fallback pick.
  func resetGroupPick(groupId: UUID, season: Int, week: Int, sport: String) async throws {
    struct Params: Encodable {
      let p_group_id: UUID
      let p_season: Int
      let p_week: Int
      let p_sport: String
    }
    _ = try await client
      .rpc("reset_group_pick", params: Params(p_group_id: groupId, p_season: season, p_week: week, p_sport: sport))
      .execute()
  }

  // sourceGroupId nil means "copy my shared pick". One-time copy, not a
  // standing sync -- Underdog is one pick per week, so this just seeds
  // the target group's week from the source's effective pick.
  func copyGroupPick(targetGroupId: UUID, sourceGroupId: UUID?, season: Int, week: Int, sport: String) async throws -> CopyPickResult {
    struct Params: Encodable {
      let p_target_group_id: UUID
      let p_source_group_id: UUID?
      let p_season: Int
      let p_week: Int
      let p_sport: String
    }
    let res = try await client
      .rpc("copy_group_pick", params: Params(p_target_group_id: targetGroupId, p_source_group_id: sourceGroupId, p_season: season, p_week: week, p_sport: sport))
      .execute()
    return try JSONDecoder().decode(CopyPickResult.self, from: res.data)
  }
}
