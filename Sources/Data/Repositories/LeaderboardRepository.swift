import Foundation
import Supabase

struct LeaderboardRepository {
  let client: SupabaseClient

  func weekly(season: Int, week: Int) async throws -> [LeaderboardWeekRow] {
    let rows: [LeaderboardWeekRow] = try await client
      .from("leaderboard_week")
      .select("id, user_id, season, week, win, loss, points")
      .eq("season", value: season)
      .eq("week", value: week)
      .order("points", ascending: false)
      .execute()
      .value
    return rows
  }

  func seasonTotals(currentSeasonOnly: Bool = true) async throws -> [LeaderboardTotalsRow] {
    var builder = client
      .from("leaderboard_totals")
      .select("id, user_id, wins, losses, pending, total_points, season")

    if currentSeasonOnly,
       let context = try? await ContextService(client: client).getCurrentContext() {
      builder = builder.eq("season", value: context.season)
    }

    let rows: [LeaderboardTotalsRow] = try await builder
      .order("total_points", ascending: false)
      .execute()
      .value
    return rows
  }
}

