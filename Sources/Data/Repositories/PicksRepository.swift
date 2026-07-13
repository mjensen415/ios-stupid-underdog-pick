import Foundation
import Supabase

enum PicksRepositoryError: Error {
  case alreadyPicked
}

struct PicksRepository {
  let client: SupabaseClient

  func myPick(season: Int, week: Int, userId: UUID) async throws -> Pick? {
    let picks: [Pick] = try await client
      .from("picks")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .eq("user_id", value: userId)
      .eq("season", value: season)
      .eq("week", value: week)
      .limit(1)
      .execute()
      .value
    return picks.first
  }

  func history(userId: UUID, limit: Int = 10) async throws -> [Pick] {
    try await client
      .from("picks")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .eq("user_id", value: userId)
      .order("season", ascending: false)
      .order("week", ascending: false)
      .limit(limit)
      .execute()
      .value
  }

  func upsertPick(season: Int, week: Int, gameId: UUID, pickedTeamId: UUID) async throws -> Pick {
    struct Insert: Encodable {
      let game_id: UUID
      let picked_team_id: UUID
      let season: Int
      let week: Int
    }
    let insert = Insert(game_id: gameId, picked_team_id: pickedTeamId, season: season, week: week)
    do {
      let picks: [Pick] = try await client
        .from("picks")
        .upsert(insert, onConflict: "user_id,season,week")
        .select("id, user_id, game_id, picked_team_id, season, week, created_at")
        .execute()
        .value
      if let pick = picks.first { return pick }
      throw PicksRepositoryError.alreadyPicked
    } catch let error as PostgrestError {
      // Unique violation or RLS rejection should be conveyed nicely
      if error.code == "23505" || error.message.localizedCaseInsensitiveContains("duplicate") {
        throw PicksRepositoryError.alreadyPicked
      }
      throw error
    } catch {
      throw error
    }
  }
}
