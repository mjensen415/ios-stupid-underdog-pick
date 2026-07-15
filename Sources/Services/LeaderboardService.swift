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

struct LeaderboardService {
  let client: SupabaseClient

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

