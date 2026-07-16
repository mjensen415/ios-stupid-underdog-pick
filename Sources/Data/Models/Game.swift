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
  public let status: String?
  public let homePoints: Int?
  public let awayPoints: Int?

  public enum CodingKeys: String, CodingKey {
    case id, season, week, status
    case homeTeam = "home_team"
    case awayTeam = "away_team"
    case homeTeamId = "home_team_id"
    case awayTeamId = "away_team_id"
    case favoriteTeamId = "favorite_team_id"
    case startTime = "start_time"
    case bettingLine = "betting_line"
    case latestSpread = "latest_spread"
    case picksLocked = "picks_locked"
    case homePoints = "home_points"
    case awayPoints = "away_points"
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

  public enum PickOutcome { case win, loss, pending }

  /// Same win/loss/pending resolution as web's PickHistoryTab.tsx
  /// pickResult() -- status must be final and both scores present, then
  /// compare against which side the picked team was on.
  public func outcome(forPickedTeamId pickedTeamId: UUID) -> PickOutcome {
    guard status == "final", let hp = homePoints, let ap = awayPoints else { return .pending }
    let pickedHome = pickedTeamId == homeTeamId
    let homeWon = hp > ap
    let won = (pickedHome && homeWon) || (!pickedHome && ap > hp)
    return won ? .win : .loss
  }
}
