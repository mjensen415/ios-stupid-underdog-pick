import Foundation
import Supabase

struct Game: Decodable, Identifiable {
  let id: UUID
  let season: Int
  let week: Int
  let homeTeam: String?
  let awayTeam: String?
  let startTimeRaw: String
  let bettingLine: String?
  let latestSpread: Double?

  enum CodingKeys: String, CodingKey {
    case id, season, week
    case homeTeam = "home_team"
    case awayTeam = "away_team"
    case startTimeRaw = "start_time"
    case bettingLine = "betting_line"
    case latestSpread = "latest_spread"
  }
}

struct GamesService {
  let client: SupabaseClient
  func fetch(season: Int, week: Int) async throws -> [Game] {
    let res = try await client.database
      .from("games")
      .select("id, season, week, home_team, away_team, start_time, betting_line, latest_spread")
      .eq("season", value: season)
      .eq("week", value: week)
      .order("start_time", ascending: true)
      .execute()
    #if DEBUG
    if let raw = String(data: res.data, encoding: .utf8) { print("[Games][RAW]", raw) }
    #endif
    return try JSONDecoder().decode([Game].self, from: res.data)
  }
}


