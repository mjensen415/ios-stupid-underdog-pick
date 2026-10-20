import Foundation
import Supabase

/// Data access for Hoops / Pucks groups. Every rule (weekly limit, dog-only,
/// lock at start, stale lines, hidden leaguemate picks) is enforced by the
/// hp_* RPCs; this just calls them and surfaces their error codes.
struct HoopsPucksService {
  let client: SupabaseClient

  struct HpError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  /// Friendly copy for whatever the RPC raised (HP_ERRORS).
  static func friendly(_ error: Error) -> String {
    if let e = error as? PostgrestError { return HP.errorMessage(e.message) }
    if let e = error as? HpError { return e.message }
    return HP.errorMessage(error.localizedDescription)
  }

  private var decoder: JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601withFallback
    return d
  }

  /// The signed-in user's groups (all sports), with their role in each.
  func myLeagues(userId: UUID) async throws -> [HpLeague] {
    struct Row: Decodable { let role: String; let hp_leagues: HpLeague? }
    let res = try await client.from("hp_members").select("role, hp_leagues(*)").eq("user_id", value: userId).execute()
    return try decoder.decode([Row].self, from: res.data).compactMap { r in
      guard var l = r.hp_leagues else { return nil }
      l.role = r.role
      return l
    }
  }

  /// One ET week's slate (Monday 00:00 to Sunday 23:59 ET).
  func games(sport: HpSport, weekStart: String) async throws -> [HpGame] {
    let b = HP.weekBoundsUtc(weekStart)
    let f = ISO8601DateFormatter()
    let res = try await client.from("daily_games")
      .select("id, sport, espn_event_id, home_espn_id, away_espn_id, start_time, status, status_detail, home_name, home_abbr, away_name, away_abbr, home_score, away_score, winner, home_ml, away_ml, spread")
      .eq("sport", value: sport.rawValue)
      .gte("start_time", value: f.string(from: b.start))
      .lt("start_time", value: f.string(from: b.end))
      .order("start_time", ascending: true)
      .execute()
    return try decoder.decode([HpGame].self, from: res.data)
  }

  func myPicks(leagueId: UUID, userId: UUID) async throws -> [HpPick] {
    let res = try await client.from("hp_picks")
      .select("game_id, side, locked_ml, locked_spread, week_start")
      .eq("league_id", value: leagueId).eq("user_id", value: userId)
      .execute()
    return try decoder.decode([HpPick].self, from: res.data)
  }

  func weeklyBoard(leagueId: UUID, weekStart: String) async throws -> [HpBoardRow] {
    struct P: Encodable { let p_league: UUID; let p_week_start: String }
    let res = try await client.rpc("hp_weekly_leaderboard", params: P(p_league: leagueId, p_week_start: weekStart)).execute()
    return try decoder.decode([HpBoardRow].self, from: res.data)
  }

  func seasonBoard(leagueId: UUID) async throws -> [HpBoardRow] {
    struct P: Encodable { let p_league: UUID }
    let res = try await client.rpc("hp_season_leaderboard", params: P(p_league: leagueId)).execute()
    return try decoder.decode([HpBoardRow].self, from: res.data)
  }

  func createLeague(name: String, sport: HpSport, picksPerWeek: Int) async throws -> HpLeague {
    struct P: Encodable { let p_name: String; let p_sport: String; let p_picks_per_week: Int; let p_is_private: Bool }
    let res = try await client.rpc("hp_create_league", params: P(p_name: name, p_sport: sport.rawValue, p_picks_per_week: picksPerWeek, p_is_private: true)).execute()
    var l = try decoder.decode(HpLeague.self, from: res.data)
    l.role = "admin"
    return l
  }

  /// Returns the joined league's id.
  func joinLeague(code: String) async throws -> UUID {
    struct P: Encodable { let p_code: String }
    let res = try await client.rpc("hp_join_league", params: P(p_code: code)).execute()
    return try decoder.decode(UUID.self, from: res.data)
  }

  func leagueSport(id: UUID) async -> HpSport? {
    struct Row: Decodable { let sport: HpSport }
    guard let res = try? await client.from("hp_leagues").select("sport").eq("id", value: id).limit(1).execute() else { return nil }
    return (try? decoder.decode([Row].self, from: res.data))?.first?.sport
  }

  func leaveLeague(id: UUID) async throws {
    struct P: Encodable { let p_league: UUID }
    _ = try await client.rpc("hp_leave_league", params: P(p_league: id)).execute()
  }

  func updatePicksPerWeek(leagueId: UUID, picksPerWeek: Int) async throws {
    struct P: Encodable { let p_league: UUID; let p_picks_per_week: Int }
    _ = try await client.rpc("hp_update_league", params: P(p_league: leagueId, p_picks_per_week: picksPerWeek)).execute()
  }

  func makePick(leagueId: UUID, gameId: UUID, side: HpSide) async throws {
    struct P: Encodable { let p_league: UUID; let p_game: UUID; let p_side: String }
    _ = try await client.rpc("hp_make_pick", params: P(p_league: leagueId, p_game: gameId, p_side: side.rawValue)).execute()
  }

  func unpick(leagueId: UUID, gameId: UUID) async throws {
    struct P: Encodable { let p_league: UUID; let p_game: UUID }
    _ = try await client.rpc("hp_unpick", params: P(p_league: leagueId, p_game: gameId)).execute()
  }

  /// Pro "Last 3": the sport's finals over the last 21 days, then each team's
  /// newest 3 by ESPN team id. Only basketball spreads show as a line
  /// (hockey's puck line isn't what Pucks scores on).
  func recentForm(sport: HpSport, now: Date = Date()) async -> [String: [FormGame]] {
    struct Row: Decodable {
      let home_name: String?; let away_name: String?
      let home_espn_id: String?; let away_espn_id: String?
      let home_score: Int?; let away_score: Int?
      let spread: Double?; let start_time: Date
    }
    let since = ISO8601DateFormatter().string(from: now.addingTimeInterval(-21 * 86_400))
    guard let res = try? await client.from("daily_games")
      .select("home_name, away_name, home_espn_id, away_espn_id, home_score, away_score, spread, start_time")
      .eq("sport", value: sport.rawValue).eq("status", value: "final").gte("start_time", value: since)
      .order("start_time", ascending: false).limit(400)
      .execute(),
      let rows = try? decoder.decode([Row].self, from: res.data)
    else { return [:] }
    return Self.groupForm(rows.map {
      RawFinal(home: $0.home_name ?? "", away: $0.away_name ?? "", homeKey: $0.home_espn_id, awayKey: $0.away_espn_id,
               homePts: $0.home_score, awayPts: $0.away_score, spread: sport == .nba ? $0.spread : nil, startTime: $0.start_time)
    })
  }

  /// Newest-first finals -> each team's newest 3, by key.
  static func groupForm(_ finals: [RawFinal], n: Int = 3) -> [String: [FormGame]] {
    var out: [String: [FormGame]] = [:]
    for g in finals {
      for key in [g.homeKey, g.awayKey].compactMap({ $0 }) {
        var list = out[key] ?? []
        guard list.count < n, let f = RecentForm.toFormGame(g, key: key, name: nil) else { continue }
        list.append(f)
        out[key] = list
      }
    }
    return out
  }
}
