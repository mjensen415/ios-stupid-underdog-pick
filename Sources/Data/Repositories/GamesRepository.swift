import Foundation
import Supabase

struct GamesRepository {
  let client: SupabaseClient

  func list(season: Int, week: Int) async throws -> [Game] {
    let games: [Game] = try await client
      .from("games")
      .select("id, start_time, status, week, season, home_team, away_team, home_team_id, away_team_id, latest_spread, betting_line, picks_locked, final")
      .eq("season", value: season)
      .eq("week", value: week)
      .order("start_time", ascending: true)
      .execute()
      .value
    return games
  }

  func detail(gameId: UUID) async throws -> Game? {
    let games: [Game] = try await client
      .from("games")
      .select("id, start_time, status, week, season, home_team, away_team, home_team_id, away_team_id, latest_spread, betting_line, picks_locked, final")
      .eq("id", value: gameId)
      .limit(1)
      .execute()
      .value
    return games.first
  }
}
