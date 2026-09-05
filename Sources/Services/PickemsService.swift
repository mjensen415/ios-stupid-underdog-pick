import Foundation
import Supabase

// Pro Ball Pickems: a second, independent NFL game mode (pick the
// straight-up winner of every game, 1pt each) -- own tables/RPCs added
// server-side, this is purely the client layer. Mirrors web's
// src/pages/Pickems.tsx + PickemsStandings.tsx data-fetching exactly.

struct PickemsGameRow: Decodable, Identifiable {
  let id: UUID
  let homeTeamId: UUID
  let awayTeamId: UUID
  let homeName: String?
  let awayName: String?
  let homeLogoUrl: String?
  let awayLogoUrl: String?
  let status: String
  let startTime: Date
  let homePoints: Int?
  let awayPoints: Int?

  enum CodingKeys: String, CodingKey {
    case id, status
    case homeTeamId = "home_team_id"
    case awayTeamId = "away_team_id"
    case homeName = "home_name"
    case awayName = "away_name"
    case homeLogoUrl = "home_logo_url"
    case awayLogoUrl = "away_logo_url"
    case startTime = "start_time"
    case homePoints = "home_points"
    case awayPoints = "away_points"
  }

  var isLocked: Bool { status != "scheduled" || startTime <= Date() }
  var isFinal: Bool { status == "final" && homePoints != nil && awayPoints != nil }
  var isLive: Bool { status == "in_progress" }
  var winnerTeamId: UUID? {
    guard isFinal, let h = homePoints, let a = awayPoints else { return nil }
    if h > a { return homeTeamId }
    if a > h { return awayTeamId }
    return nil
  }
}

private struct PickemsPickRow: Decodable {
  let game_id: UUID
  let picked_team_id: UUID
  let acting_as_profile_id: UUID?
}

private struct PickemsTiebreakerRow: Decodable {
  let guessed_total_points: Int
  let acting_as_profile_id: UUID?
}

private struct WeekRow: Decodable {
  let week: Int
}

struct ManagedProfile: Decodable, Identifiable, Equatable {
  let id: UUID
  let displayName: String
  let isActive: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case isActive = "is_active"
  }
}

struct GroupPickemsRow: Decodable, Identifiable {
  var id: UUID { userId }
  let groupId: UUID
  let userId: UUID
  let displayName: String
  let role: String
  let seasonCorrect: Int
  let seasonTotalPicks: Int
  let weekCorrect: Int
  let weekTotalPicks: Int
  let guessedTotalPoints: Int?

  enum CodingKeys: String, CodingKey {
    case groupId = "group_id"
    case userId = "user_id"
    case displayName = "display_name"
    case role
    case seasonCorrect = "season_correct"
    case seasonTotalPicks = "season_total_picks"
    case weekCorrect = "week_correct"
    case weekTotalPicks = "week_total_picks"
    case guessedTotalPoints = "guessed_total_points"
  }
}

struct PickemsService {
  let client: SupabaseClient

  private var dateDecoder: JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601withFallback
    return d
  }

  func fetchGames(season: Int, week: Int, sport: String = "nfl") async throws -> [PickemsGameRow] {
    let res = try await client
      .from("v_games_named")
      .select("id, home_team_id, away_team_id, home_name, away_name, home_logo_url, away_logo_url, status, start_time, home_points, away_points")
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
      .order("start_time", ascending: true)
      .execute()
    return try dateDecoder.decode([PickemsGameRow].self, from: res.data)
  }

  func fetchDistinctWeeks(season: Int, sport: String = "nfl") async throws -> [Int] {
    let res = try await client
      .from("games")
      .select("week")
      .eq("season", value: season)
      .eq("sport", value: sport)
      .execute()
    let rows = try JSONDecoder().decode([WeekRow].self, from: res.data)
    return Array(Set(rows.map { $0.week })).sorted()
  }

  // Fetches every row for this user (own + all children) and filters by
  // actor client-side, rather than relying on a server-side IS NULL filter
  // whose exact postgrest-swift call signature isn't worth guessing at.
  func fetchMyPicks(userId: UUID, gameIds: [UUID], actingAsProfileId: UUID? = nil) async throws -> [UUID: UUID] {
    guard !gameIds.isEmpty else { return [:] }
    let res = try await client
      .from("pickems_picks")
      .select("game_id, picked_team_id, acting_as_profile_id")
      .eq("user_id", value: userId)
      .in("game_id", values: gameIds)
      .execute()
    let rows = try JSONDecoder().decode([PickemsPickRow].self, from: res.data)
      .filter { $0.acting_as_profile_id == actingAsProfileId }
    return Dictionary(uniqueKeysWithValues: rows.map { ($0.game_id, $0.picked_team_id) })
  }

  func fetchTiebreaker(userId: UUID, season: Int, week: Int, sport: String = "nfl", actingAsProfileId: UUID? = nil) async throws -> Int? {
    let res = try await client
      .from("pickems_tiebreakers")
      .select("guessed_total_points, acting_as_profile_id")
      .eq("user_id", value: userId)
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
      .execute()
    return try JSONDecoder().decode([PickemsTiebreakerRow].self, from: res.data)
      .first { $0.acting_as_profile_id == actingAsProfileId }?.guessed_total_points
  }

  func submitPick(gameId: UUID, pickedTeamId: UUID, actingAsProfileId: UUID? = nil) async throws {
    struct Params: Encodable { let p_game_id: UUID; let p_picked_team_id: UUID; let p_acting_as_profile_id: UUID? }
    _ = try await client.rpc("submit_pickems_pick", params: Params(p_game_id: gameId, p_picked_team_id: pickedTeamId, p_acting_as_profile_id: actingAsProfileId)).execute()
  }

  func clearPick(gameId: UUID) async throws {
    struct Params: Encodable { let p_game_id: UUID }
    _ = try await client.rpc("clear_pickems_pick", params: Params(p_game_id: gameId)).execute()
  }

  func submitTiebreaker(season: Int, week: Int, sport: String = "nfl", guess: Int, actingAsProfileId: UUID? = nil) async throws {
    struct Params: Encodable { let p_season: Int; let p_week: Int; let p_sport: String; let p_guessed_total_points: Int; let p_acting_as_profile_id: UUID? }
    _ = try await client.rpc("submit_pickems_tiebreaker", params: Params(p_season: season, p_week: week, p_sport: sport, p_guessed_total_points: guess, p_acting_as_profile_id: actingAsProfileId)).execute()
  }

  func fetchManagedProfiles() async throws -> [ManagedProfile] {
    let res = try await client
      .from("managed_profiles")
      .select("id, display_name, is_active")
      .eq("is_active", value: true)
      .order("created_at", ascending: true)
      .execute()
    return try JSONDecoder().decode([ManagedProfile].self, from: res.data)
  }

  func addManagedProfile(ownerUserId: UUID, displayName: String) async throws {
    struct Insert: Encodable { let owner_user_id: UUID; let display_name: String }
    _ = try await client.from("managed_profiles").insert(Insert(owner_user_id: ownerUserId, display_name: displayName)).execute()
  }

  func removeManagedProfile(id: UUID) async throws {
    struct Update: Encodable { let is_active: Bool }
    _ = try await client.from("managed_profiles").update(Update(is_active: false)).eq("id", value: id).execute()
  }

  func fetchGroupLeaderboard(groupId: UUID, season: Int, sport: String = "nfl", week: Int?) async throws -> [GroupPickemsRow] {
    struct Params: Encodable { let p_group_id: UUID; let p_season: Int; let p_sport: String; let p_week: Int? }
    let res = try await client
      .rpc("get_group_pickems_leaderboard", params: Params(p_group_id: groupId, p_season: season, p_sport: sport, p_week: week))
      .execute()
    return try JSONDecoder().decode([GroupPickemsRow].self, from: res.data)
  }
}
