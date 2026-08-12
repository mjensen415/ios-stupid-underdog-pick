import Foundation
import Supabase
// Uses canonical Game model from Sources/Data/Models/Game.swift

struct GamesService {
  let client: SupabaseClient

  func fetch(season: Int, week: Int, sport: String = "cfb") async throws -> [Game] {
    // v_games_named, not the raw games table -- see Game.CodingKeys for why.
    let res = try await client
      .from("v_games_named")
      .select("""
        id, season, week, home_name, away_name, home_team_id, away_team_id, favorite_team_id, start_time, betting_line, latest_spread, picks_locked, sport
      """)
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
      .order("start_time", ascending: true)
      .execute()

    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withFallback
    return try dec.decode([Game].self, from: res.data)
  }

  func distinctWeeks(forSeason season: Int, sport: String = "cfb") async throws -> [Int] {
    let res = try await client
      .from("games")
      .select("week", head: false, count: nil)
      .eq("season", value: season)
      .eq("sport", value: sport)
      .order("week", ascending: true)
      .execute()
    struct W: Decodable { let week: Int }
    let weeks = try JSONDecoder().decode([W].self, from: res.data).map { $0.week }
    return Array(Set(weeks)).sorted()
  }
}

extension JSONDecoder.DateDecodingStrategy {
  static var iso8601withFallback: JSONDecoder.DateDecodingStrategy {
    .custom { decoder in
      let c = try decoder.singleValueContainer()
      let s = try c.decode(String.self)
      if let d = ISO8601DateFormatter().date(from: s) { return d }
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.timeZone = TimeZone(secondsFromGMT: 0)
      f.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
      if let d = f.date(from: s) { return d }
      throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported date: \(s)")
    }
  }
}

