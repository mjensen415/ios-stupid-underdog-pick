import Foundation

public struct Pick: Decodable, Identifiable {
  public let id: UUID
  public let user_id: UUID
  public let game_id: UUID
  public let picked_team_id: UUID
  public let season: Int
  public let week: Int
  public let created_at: String?
  /// Pro Ball only: home-relative line captured when the pick was made.
  /// Scoring uses it instead of the game's (moving) line. Nil for CFB.
  public let locked_spread: Double?
}

extension Pick {
  /// Home-relative spread this pick is scored on.
  public func scoredSpread(on game: Game) -> Double? { locked_spread ?? game.latestSpread }

  /// The picked team's line from its own side: +7 means getting 7 points.
  public func pickedLine(on game: Game) -> Double? {
    guard let s = scoredSpread(on: game) else { return nil }
    return picked_team_id == game.homeTeamId ? s : -s
  }

  /// Points a win would bank -- only while the pick is the underdog on the
  /// line it's scored on (outright win required, points = the spread).
  public func winPoints(on game: Game) -> Double? {
    guard let line = pickedLine(on: game), line > 0 else { return nil }
    return line
  }

  /// The game's line now, from the picked team's side, when a locked line
  /// has since moved. Nil when unlocked or unchanged.
  public func movedLine(on game: Game) -> Double? {
    guard let locked = locked_spread, let now = game.latestSpread, now != locked else { return nil }
    return picked_team_id == game.homeTeamId ? now : -now
  }

  /// One-line explanation under the pick when the line matters:
  /// "Locked at +7 · line now -1.5", or a no-points warning.
  public func lineNote(on game: Game) -> String? {
    guard game.status != "final" else { return nil }
    func fmt(_ v: Double) -> String {
      let n = v == v.rounded() ? String(format: "%.0f", abs(v)) : String(format: "%.1f", abs(v))
      return v > 0 ? "+\(n)" : v < 0 ? "-\(n)" : "PK"
    }
    if let line = pickedLine(on: game), line <= 0 {
      return "Now the favorite (\(fmt(line))) -- no points if they win"
    }
    if let line = pickedLine(on: game), let now = movedLine(on: game) {
      return "Locked at \(fmt(line)) · line now \(fmt(now))"
    }
    return nil
  }
}
