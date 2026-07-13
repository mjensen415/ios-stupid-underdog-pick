import Foundation

public struct Game: Decodable, Identifiable {
  public let id: UUID
  public let season: Int
  public let week: Int
  public let homeTeam: String?
  public let awayTeam: String?
  public let homeTeamId: UUID?
  public let awayTeamId: UUID?
  public let favoriteTeamId: UUID?
  public let startTime: Date
  public let bettingLine: String?
  public let latestSpread: Double?
  public let picksLocked: Bool?

  public enum CodingKeys: String, CodingKey {
    case id, season, week
    case homeTeam = "home_team"
    case awayTeam = "away_team"
    case homeTeamId = "home_team_id"
    case awayTeamId = "away_team_id"
    case favoriteTeamId = "favorite_team_id"
    case startTime = "start_time"
    case bettingLine = "betting_line"
    case latestSpread = "latest_spread"
    case picksLocked = "picks_locked"
  }
}
