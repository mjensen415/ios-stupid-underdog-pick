import Foundation
import Supabase

/// Lock-in spread re-check -- port of the web's fetchCurrentDogSpread /
/// movedSpread flow in src/pages/IndexBold.tsx. Games load once per week
/// with no polling, so the pick card can sit on a line that has moved since
/// it opened. Right before locking, re-read the game's line; if it moved,
/// ask "lock in at +X?" instead of silently picking at the old number.
enum LineCheck: Equatable {
  /// Same line (or nothing to compare): lock in.
  case unchanged
  /// Same underdog, new number (positive, the dog's points).
  case moved(Double)
  /// The other team is the underdog now (or it's a pick'em). The card's
  /// teams are wrong, so don't offer a one-tap confirm.
  case flipped
}

enum LineRecheck {
  /// `currentHomeSpread` is home-relative like games.latest_spread
  /// (negative = home favored). Like the web, a missing value on either
  /// side never blocks the pick.
  static func evaluate(shownHomeSpread: Double?, currentHomeSpread: Double?) -> LineCheck {
    guard let shown = shownHomeSpread, let current = currentHomeSpread, shown != 0 else { return .unchanged }
    if current == 0 || (current < 0) != (shown < 0) { return .flipped }
    return abs(current - shown) > 0.001 ? .moved(abs(current)) : .unchanged
  }

  /// The game's current home-relative line from the games table, with the
  /// web's priority (closing first only once the game is final). Nil on any
  /// error -- the caller then locks in as before.
  static func currentHomeSpread(gameId: UUID, client: SupabaseClient) async -> Double? {
    struct Row: Decodable {
      let status: String?
      let home_points: Int?
      let away_points: Int?
      let closing_spread: Double?
      let latest_spread: Double?
      let home_spread: Double?
    }
    guard let res = try? await client
      .from("games")
      .select("status, home_points, away_points, closing_spread, latest_spread, home_spread")
      .eq("id", value: gameId)
      .limit(1)
      .execute(),
      let row = (try? JSONDecoder().decode([Row].self, from: res.data))?.first
    else { return nil }
    let isFinal = row.status == "final" || (row.home_points != nil && row.away_points != nil)
    return isFinal
      ? row.closing_spread ?? row.latest_spread ?? row.home_spread
      : row.latest_spread ?? row.home_spread ?? row.closing_spread
  }
}
