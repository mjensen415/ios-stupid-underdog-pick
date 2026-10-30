import Foundation

// "Last 3" recent form (SUP Pro): a team's most recent finished games, from
// its own side -- result, score, opponent, and the line it got. Port of the
// web's src/lib/recentForm.ts (keep in sync).

struct FormGame: Equatable {
  let won: Bool
  /// A tie shows as "T" (rare: only in data without overtime results).
  let tie: Bool
  let ourPts: Int
  let theirPts: Int
  let opponent: String
  let away: Bool
  /// The team's own line: +3.5 = it was getting 3.5 (the dog); nil when no line.
  let line: Double?
  /// Won outright as the underdog, the result SUP scores.
  let dogWin: Bool
  /// Kickoff / tip-off.
  let date: Date?
}

struct RawFinal {
  let home: String
  let away: String
  let homeKey: String?
  let awayKey: String?
  let homePts: Int?
  let awayPts: Int?
  /// Home-relative spread: positive = home is the dog.
  let spread: Double?
  var startTime: Date? = nil
  /// Short names (v_games_named home_short/away_short) for the opponent
  /// label; nil = use the full name.
  var homeShort: String? = nil
  var awayShort: String? = nil
}

enum RecentForm {
  /// From one team's side. `key` matches homeKey/awayKey (team id), `name`
  /// is a fallback match on the name. Nil when the game isn't this team's.
  static func toFormGame(_ g: RawFinal, key: String?, name: String?) -> FormGame? {
    guard let hp = g.homePts, let ap = g.awayPts else { return nil }
    let isHome = (key != nil && g.homeKey == key) || (name != nil && g.home == name)
    let isAway = !isHome && ((key != nil && g.awayKey == key) || (name != nil && g.away == name))
    guard isHome || isAway else { return nil }
    let ours = isHome ? hp : ap
    let theirs = isHome ? ap : hp
    let line: Double? = (g.spread == nil || g.spread == 0) ? nil : (isHome ? g.spread! : -g.spread!)
    let won = ours > theirs
    return FormGame(
      won: won, tie: ours == theirs, ourPts: ours, theirPts: theirs,
      opponent: isHome ? (g.awayShort ?? g.away) : (g.homeShort ?? g.home), away: !isHome,
      line: line, dogWin: won && (line ?? 0) > 0, date: g.startTime
    )
  }

  static func record(_ games: [FormGame]) -> String {
    let w = games.filter(\.won).count
    let t = games.filter(\.tie).count
    return t > 0 ? "\(w)-\(games.count - w - t)-\(t)" : "\(w)-\(games.count - w)"
  }

  static func fmtLine(_ line: Double?) -> String {
    guard let line else { return "" }
    return line > 0 ? "+\(jsNumber(line))" : jsNumber(line)
  }

  /// "10/17" in US Eastern, the calendar day the game was played.
  static func fmtDate(_ d: Date?) -> String {
    guard let d else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = HP.eastern
    f.dateFormat = "M/d"
    return f.string(from: d)
  }
}
