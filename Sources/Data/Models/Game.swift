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

  /// Nothing in the sync pipeline actually populates favorite_team_id --
  /// it's null on every row in production. Derive it from latest_spread
  /// instead (home-team-relative: negative means home is favored, positive
  /// means home is the underdog), same convention the web app already uses.
  /// Falls back to the raw column first in case that ever changes.
  public var derivedFavoriteTeamId: UUID? {
    if let favoriteTeamId { return favoriteTeamId }
    guard let spread = latestSpread else { return nil }
    if spread < 0 { return homeTeamId }
    if spread > 0 { return awayTeamId }
    return nil
  }

  public var derivedUnderdogTeamId: UUID? {
    guard let fav = derivedFavoriteTeamId else { return nil }
    return fav == homeTeamId ? awayTeamId : homeTeamId
  }

  /// Underdog's spread as a positive number, regardless of which side of
  /// zero latest_spread was recorded on.
  public var underdogSpread: Double? {
    guard let spread = latestSpread else { return nil }
    return abs(spread)
  }
}
