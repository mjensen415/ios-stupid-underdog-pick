import Foundation
import Supabase

struct WeeklyRow: Decodable, Identifiable {
  let id: UUID
  let user_id: UUID
  let season: Int
  let week: Int
  let win: Int
  let loss: Int
  let points: Double
}

struct TotalsRow: Decodable, Identifiable {
  let id: UUID
  let user_id: UUID
  let season: Int?
  let wins: Int
  let losses: Int
  let pending: Int
  let total_points: Double
}

struct LeaderboardServiceFlat {
  let client: SupabaseClient

  func weekly(season: Int, week: Int) async throws -> [WeeklyRow] {
    let res = try await client
      .from("leaderboard_week")
      .select("id, user_id, season, week, win, loss, points")
      .eq("season", value: season)
      .eq("week", value: week)
      .order("points", ascending: false)
      .execute()
    return try JSONDecoder().decode([WeeklyRow].self, from: res.data)
  }

  func totals(season: Int) async throws -> [TotalsRow] {
    let res = try await client
      .from("leaderboard_totals")
      .select("id, user_id, season, wins, losses, pending, total_points")
      .eq("season", value: season)
      .order("total_points", ascending: false)
      .execute()
    return try JSONDecoder().decode([TotalsRow].self, from: res.data)
  }
}

import Foundation
import Supabase

struct WeeklyLeaderboardRow: Decodable, Identifiable {
  let id: UUID
  let userId: UUID
  let season: Int
  let week: Int
  let win: Int?
  let loss: Int?
  let points: Double?

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case season, week
    case win, loss, points
  }
}

struct TotalsLeaderboardRow: Decodable, Identifiable {
  let id: UUID
  let userId: UUID
  let season: Int?
  let wins: Int?
  let losses: Int?
  let pending: Int?
  let totalPoints: Double?

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case season
    case wins, losses, pending
    case totalPoints = "total_points"
  }
}

/// Leaderboard rows only carry user_id -- looks up display names separately
/// (profiles.display_name is public-read by RLS) rather than showing the
/// raw UUID, matching the same inline-join pattern GamesViewModel already
/// uses for team logos.
func fetchDisplayNames(client: SupabaseClient, userIds: [UUID]) async -> [UUID: String] {
  let distinct = Array(Set(userIds))
  guard !distinct.isEmpty else { return [:] }
  do {
    struct P: Decodable { let user_id: UUID; let display_name: String? }
    let res = try await client
      .from("profiles")
      .select("user_id, display_name")
      .in("user_id", values: distinct)
      .execute()
    let profiles = try JSONDecoder().decode([P].self, from: res.data)
    return Dictionary(uniqueKeysWithValues: profiles.compactMap { p -> (UUID, String)? in
      guard let name = p.display_name, !name.isEmpty else { return nil }
      return (p.user_id, name)
    })
  } catch {
    return [:]
  }
}

/// All-time career totals for one user, aggregated across every season --
/// backed by v_leaderboard_totals_named, the same pre-aggregated view the
/// web app already uses for its own "your stats" widget. Distinct from
/// leaderboard_totals, which has one row per (user_id, season) and has no
/// single combined-across-seasons row of its own.
struct CareerTotals: Decodable {
  let wins: Int?
  let losses: Int?
  let totalPoints: Double?

  enum CodingKeys: String, CodingKey {
    case wins, losses
    case totalPoints = "total_points"
  }
}

/// Row shape returned by the get_season_leaderboard RPC -- live-computed
/// from picks/games via pick_points_v -> leaderboard_season_v, unaffected
/// by the leaderboard_totals season-grouping bug. Used for the Season
/// Leaderboard screen instead of reading leaderboard_totals directly.
struct SeasonLeaderboardRow: Decodable, Identifiable {
  var id: UUID { userId }
  let season: Int
  let userId: UUID
  let displayName: String?
  let seasonPoints: Double?
  let totalWins: Int?
  let totalLosses: Int?
  let lastWeekPlayed: Int?

  enum CodingKeys: String, CodingKey {
    case season
    case userId = "user_id"
    case displayName = "display_name"
    case seasonPoints = "season_points"
    case totalWins = "total_wins"
    case totalLosses = "total_losses"
    case lastWeekPlayed = "last_week_played"
  }
}

struct MyRank: Decodable {
  let rank: Int
  let points: Double
  let wins: Int
  let losses: Int
  let totalPlayers: Int

  enum CodingKeys: String, CodingKey {
    case rank, points, wins, losses
    case totalPlayers = "total_players"
  }
}

struct LeaderboardService {
  let client: SupabaseClient

  /// All-time career record -- summed client-side across every season row,
  /// since leaderboard_totals has one row per (user_id, season), not a
  /// single combined-across-seasons row per user.
  func fetchMyCareerTotals(userId: UUID) async throws -> CareerTotals? {
    let seasons = try await fetchMySeasonTotals(userId: userId)
    guard !seasons.isEmpty else { return nil }
    return CareerTotals(
      wins: seasons.reduce(0) { $0 + ($1.wins ?? 0) },
      losses: seasons.reduce(0) { $0 + ($1.losses ?? 0) },
      totalPoints: seasons.reduce(0) { $0 + ($1.totalPoints ?? 0) }
    )
  }

  /// Season-by-season career record for one user (one row per season played).
  func fetchMySeasonTotals(userId: UUID, sport: String = "cfb") async throws -> [TotalsLeaderboardRow] {
    let res = try await client
      .from("leaderboard_totals")
      .select("id, user_id, season, wins, losses, pending, total_points")
      .eq("user_id", value: userId)
      .eq("sport", value: sport)
      .order("season", ascending: false)
      .execute()
    return try JSONDecoder().decode([TotalsLeaderboardRow].self, from: res.data)
  }

  /// Season leaderboard standings via the same live-computed RPC web's
  /// Leaderboard.tsx already uses -- not leaderboard_totals, which has no
  /// season-scoped correctness guarantee for cross-user standings.
  func fetchSeasonLeaderboard(season: Int, sport: String = "cfb") async throws -> [SeasonLeaderboardRow] {
    struct Params: Encodable {
      let p_season: Int
      let p_sport: String
    }
    let res = try await client
      .rpc("get_season_leaderboard", params: Params(p_season: season, p_sport: sport))
      .execute()
    return try JSONDecoder().decode([SeasonLeaderboardRow].self, from: res.data)
  }

  func fetchWeek(season: Int, week: Int, sport: String = "cfb") async throws -> [WeeklyLeaderboardRow] {
    let res = try await client
      .from("leaderboard_week")
      .select("id, user_id, season, week, win, loss, points")
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
      .order("points", ascending: false)
      .execute()

    return try JSONDecoder().decode([WeeklyLeaderboardRow].self, from: res.data)
  }

  /// Cheap single-row "my rank" lookup via get_my_rank, instead of pulling
  /// the entire ordered leaderboard just to find one user's position --
  /// backs Home's pick-status card. p_week nil = season-overall rank.
  func fetchMyRank(userId: UUID, season: Int, week: Int? = nil, sport: String = "cfb") async throws -> MyRank? {
    struct Params: Encodable { let p_user_id: UUID; let p_season: Int; let p_week: Int?; let p_sport: String }
    let res = try await client
      .rpc("get_my_rank", params: Params(p_user_id: userId, p_season: season, p_week: week, p_sport: sport))
      .execute()
    return try JSONDecoder().decode([MyRank].self, from: res.data).first
  }

  /// Current consecutive-weeks-covered streak (get_user_streak, W4) --
  /// mirrors web's Home.tsx streak query.
  func fetchStreak(userId: UUID, season: Int, sport: String = "cfb") async throws -> Int {
    struct Params: Encodable { let p_user_id: UUID; let p_season: Int; let p_sport: String }
    let res = try await client
      .rpc("get_user_streak", params: Params(p_user_id: userId, p_season: season, p_sport: sport))
      .execute()
    return try JSONDecoder().decode(Int.self, from: res.data)
  }

  func fetchTotals(season: Int?, sport: String = "cfb") async throws -> [TotalsLeaderboardRow] {
    var builder = client
      .from("leaderboard_totals")
      .select("id, user_id, season, wins, losses, pending, total_points")
      .eq("sport", value: sport)

    if let season { builder = builder.eq("season", value: season) }

    let res = try await builder
      .order("total_points", ascending: false)
      .execute()
    return try JSONDecoder().decode([TotalsLeaderboardRow].self, from: res.data)
  }
}

