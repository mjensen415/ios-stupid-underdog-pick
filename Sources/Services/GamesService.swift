import Foundation
import Supabase
// Uses canonical Game model from Sources/Data/Models/Game.swift

struct GamesService {
  let client: SupabaseClient

  /// Short-name columns (home_short / away_short) on v_games_named. They
  /// ship separately from the app, so the first fetch asks for them and,
  /// if the view doesn't have them yet, retries without and stops asking.
  static var shortNamesAvailable = true
  static let baseColumns = "id, season, week, status, home_name, away_name, home_team_id, away_team_id, favorite_team_id, start_time, betting_line, latest_spread, picks_locked, home_points, away_points, sport"

  func fetch(season: Int, week: Int, sport: String = "cfb") async throws -> [Game] {
    // v_games_named, not the raw games table -- see Game.CodingKeys for why.
    func run(_ columns: String) async throws -> [Game] {
      let res = try await client
        .from("v_games_named")
        .select(columns)
        .eq("season", value: season)
        .eq("week", value: week)
        .eq("sport", value: sport)
        .order("start_time", ascending: true)
        .execute()
      let dec = JSONDecoder()
      dec.dateDecodingStrategy = .iso8601withFallback
      return try dec.decode([Game].self, from: res.data)
    }
    if Self.shortNamesAvailable {
      do {
        return try await run(Self.baseColumns + ", home_short, away_short")
      } catch where isMissingColumn(error) {
        Self.shortNamesAvailable = false
      }
    }
    return try await run(Self.baseColumns)
  }

  /// Weeks that have games. Server-side distinct (get_game_weeks): pulling
  /// every game's week hit PostgREST's 1000-row cap for CFB, so the current
  /// week and later silently fell off the week menu.
  func distinctWeeks(forSeason season: Int, sport: String = "cfb") async throws -> [Int] {
    try await fetchGameWeeks(client: client, season: season, sport: sport)
  }
}

/// Week status from get_week_pick_window, counted on the real games table.
/// v_games_named hides CFB games with no line yet, so a new week (lines not
/// posted) looked empty and Home/My Picks said "Missed".
struct WeekPickWindow: Decodable {
  let upcoming: Int      // games not yet kicked off, lined or not
  let lined_open: Int    // of those, games with a line (pickable now)
}

func fetchWeekPickWindow(client: SupabaseClient, season: Int, week: Int, sport: String) async -> WeekPickWindow? {
  struct Params: Encodable { let p_season: Int; let p_week: Int; let p_sport: String }
  guard let res = try? await client.rpc("get_week_pick_window", params: Params(p_season: season, p_week: week, p_sport: sport)).execute()
  else { return nil }
  return try? JSONDecoder().decode([WeekPickWindow].self, from: res.data).first
}

func fetchGameWeeks(client: SupabaseClient, season: Int, sport: String) async throws -> [Int] {
  struct Params: Encodable { let p_season: Int; let p_sport: String }
  let res = try await client.rpc("get_game_weeks", params: Params(p_season: season, p_sport: sport)).execute()
  return try JSONDecoder().decode([Int].self, from: res.data).sorted()
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


/// PostgREST "column does not exist" (42703) -- used to fall back when an
/// optional column hasn't shipped yet.
func isMissingColumn(_ error: Error) -> Bool {
  if let e = error as? PostgrestError { return e.code == "42703" }
  return String(describing: error).contains("42703")
}

/// Runs a v_games_named query with the short-name columns appended when the
/// view has them, else without (same fallback as GamesService.fetch). `run`
/// gets the column list to select.
func withShortNameColumns(_ base: String, _ run: (String) async throws -> Data) async throws -> Data {
  if GamesService.shortNamesAvailable {
    do { return try await run(base + ", home_short, away_short") } catch where isMissingColumn(error) {
      GamesService.shortNamesAvailable = false
    }
  }
  return try await run(base)
}
