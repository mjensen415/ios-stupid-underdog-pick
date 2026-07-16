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

struct LeaderboardService {
  let client: SupabaseClient

  func fetchMyCareerTotals(userId: UUID) async throws -> CareerTotals? {
    let res = try await client
      .from("v_leaderboard_totals_named")
      .select("wins, losses, total_points")
      .eq("user_id", value: userId)
      .limit(1)
      .execute()
    return try JSONDecoder().decode([CareerTotals].self, from: res.data).first
  }

  /// Season-by-season career record for one user (one row per season played).
  func fetchMySeasonTotals(userId: UUID) async throws -> [TotalsLeaderboardRow] {
    let res = try await client
      .from("leaderboard_totals")
      .select("id, user_id, season, wins, losses, pending, total_points")
      .eq("user_id", value: userId)
      .order("season", ascending: false)
      .execute()
    return try JSONDecoder().decode([TotalsLeaderboardRow].self, from: res.data)
  }

  func fetchWeek(season: Int, week: Int) async throws -> [WeeklyLeaderboardRow] {
    let res = try await client
      .from("leaderboard_week")
      .select("id, user_id, season, week, win, loss, points")
      .eq("season", value: season)
      .eq("week", value: week)
      .order("points", ascending: false)
      .execute()

    return try JSONDecoder().decode([WeeklyLeaderboardRow].self, from: res.data)
  }

  func fetchTotals(season: Int?) async throws -> [TotalsLeaderboardRow] {
    var builder = client
      .from("leaderboard_totals")
      .select("id, user_id, season, wins, losses, pending, total_points")

    if let season { builder = builder.eq("season", value: season) }

    let res = try await builder
      .order("total_points", ascending: false)
      .execute()
    return try JSONDecoder().decode([TotalsLeaderboardRow].self, from: res.data)
  }
}

