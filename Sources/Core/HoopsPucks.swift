import Foundation

// Hoops (pro basketball) and Pucks (pro hockey) weekly underdog groups --
// pure logic, ported from the web's src/lib/hoopsPucks.ts (keep in sync).
// The SQL is the source of truth (hp_underdog_side, hp_week_of,
// hp_pick_results); every pick rule is enforced server-side by the hp_* RPCs,
// so this only drives what the screen shows.
//
// 'nba'/'nhl' are internal ids only. Copy says "pro basketball"/"pro hockey"
// and teams show by city/location only (daily_games.home_name/away_name are
// already city-only). Free to play: SUP never holds or takes money.

enum HpSport: String, Codable, CaseIterable, Identifiable {
  case nba, nhl
  var id: String { rawValue }

  /// feature_flags key; the server checks the same flag (_hp_enabled).
  var flag: String { self == .nba ? FeatureFlagKey.hoops : FeatureFlagKey.pucks }
  var name: String { self == .nba ? "Hoops" : "Pucks" }
  var noun: String { self == .nba ? "pro basketball" : "pro hockey" }
  var start: String { self == .nba ? "tip-off" : "puck drop" }
  var overtime: String { self == .nba ? "Overtime counts." : "Overtime and shootouts count." }
  var other: HpSport { self == .nba ? .nhl : .nba }
  /// Path segment for the self-hosted logos on the website.
  var logoFolder: String { rawValue }
  /// Path segment for ESPN game pages (where-to-watch).
  var watchSport: WatchSport { self == .nba ? .nba : .nhl }
}

enum HpSide: String, Codable { case home, away }

enum HpPickResult: String { case pending, win, loss, void }

struct HpGame: Decodable, Identifiable, Equatable {
  let id: UUID
  let sport: HpSport
  let espn_event_id: String?
  let home_espn_id: String?
  let away_espn_id: String?
  let start_time: Date
  let status: String
  let status_detail: String?
  /// City/location label, e.g. "San Jose" or "New York (NYR)".
  let home_name: String
  let home_abbr: String?
  let away_name: String
  let away_abbr: String?
  let home_score: Int?
  let away_score: Int?
  let winner: HpSide?
  let home_ml: Int?
  let away_ml: Int?
  /// Home-relative point spread: +4.5 = home gets 4.5 (home is the dog).
  let spread: Double?

  func name(_ side: HpSide) -> String { side == .home ? home_name : away_name }
  func abbr(_ side: HpSide) -> String? { side == .home ? home_abbr : away_abbr }
  func ml(_ side: HpSide) -> Int? { side == .home ? home_ml : away_ml }
  func score(_ side: HpSide) -> Int? { side == .home ? home_score : away_score }
  func espnTeamId(_ side: HpSide) -> String? { side == .home ? home_espn_id : away_espn_id }
}

struct HpLeague: Decodable, Identifiable, Equatable {
  let id: UUID
  let name: String
  let sport: HpSport
  let picks_per_week: Int
  let join_code: String
  let is_private: Bool
  /// The sport's one Global league (open to everyone, one-tap join).
  var is_global: Bool = false
  /// From hp_members (not a column on hp_leagues). Nil only for the sport's
  /// Global league when you haven't joined it yet.
  var role: String?

  enum CodingKeys: String, CodingKey { case id, name, sport, picks_per_week, join_code, is_private, is_global }

  init(id: UUID, name: String, sport: HpSport, picks_per_week: Int, join_code: String, is_private: Bool,
       is_global: Bool = false, role: String? = "member") {
    self.id = id; self.name = name; self.sport = sport; self.picks_per_week = picks_per_week
    self.join_code = join_code; self.is_private = is_private; self.is_global = is_global; self.role = role
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    sport = try c.decode(HpSport.self, forKey: .sport)
    picks_per_week = try c.decode(Int.self, forKey: .picks_per_week)
    join_code = try c.decode(String.self, forKey: .join_code)
    is_private = try c.decode(Bool.self, forKey: .is_private)
    is_global = try c.decodeIfPresent(Bool.self, forKey: .is_global) ?? false
    role = nil
  }

  var isAdmin: Bool { role == "admin" }
  var isMember: Bool { role != nil }
}

struct HpPick: Decodable, Equatable {
  let game_id: UUID
  let side: HpSide
  let locked_ml: Int?
  let locked_spread: Double?
  /// ET Monday, "YYYY-MM-DD".
  let week_start: String
}

struct HpBoardRow: Decodable, Identifiable, Equatable {
  let user_id: UUID
  let display_name: String
  let points: Double
  let correct: Int
  let picks_used: Int
  let pending: Int
  let best_hit: Double
  let rank: Int
  let weeks_won: Int?
  var id: UUID { user_id }
}

enum HP {
  // MARK: Dogs and points

  /// Payout points for a winning dog: +150 -> 1.5. Favorites/invalid lines score 0.
  static func mlToPoints(_ ml: Int?) -> Double {
    guard let ml, ml >= 100 else { return 0 }
    return Double(ml) / 100
  }

  /// Side with the plus-money line (>= +100) longer than the other's; nil for pick'em or missing odds.
  static func underdogSide(homeMl: Int?, awayMl: Int?) -> HpSide? {
    guard let h = homeMl, let a = awayMl else { return nil }
    if h >= 100 && h > a { return .home }
    if a >= 100 && a > h { return .away }
    return nil
  }

  /// Dog by point spread (home-relative: +4.5 = home gets 4.5). Nil for pick'em or no line.
  static func spreadDogSide(_ spread: Double?) -> HpSide? {
    guard let s = spread, s.isFinite, s != 0 else { return nil }
    return s > 0 ? .home : .away
  }

  /// The underdog under the sport's scoring rule (owner decision Oct 20 2026):
  /// Hoops by the point spread, Pucks by the moneyline.
  static func dogSide(sport: HpSport, homeMl: Int?, awayMl: Int?, spread: Double?) -> HpSide? {
    sport == .nba ? spreadDogSide(spread) : underdogSide(homeMl: homeMl, awayMl: awayMl)
  }

  static func dogSide(_ g: HpGame) -> HpSide? {
    dogSide(sport: g.sport, homeMl: g.home_ml, awayMl: g.away_ml, spread: g.spread)
  }

  /// Points the dog was getting, from its side.
  static func dogSpread(_ spread: Double?) -> Double? {
    guard let s = spread, s.isFinite, s != 0 else { return nil }
    return abs(s)
  }

  /// Points a winning pick banks: Hoops the spread, Pucks the moneyline payout.
  static func pickPoints(sport: HpSport, lockedMl: Int?, lockedSpread: Double?) -> Double {
    sport == .nba ? (dogSpread(lockedSpread) ?? 0) : mlToPoints(lockedMl)
  }

  // MARK: Formatting (matches the web's number output)

  /// "+3.5" for a dog getting 3.5.
  static func fmtSpread(_ pts: Double?) -> String {
    guard let pts else { return "—" }
    return "+" + jsNumber((pts * 10).rounded() / 10)
  }

  static func fmtMl(_ ml: Int?) -> String {
    guard let ml else { return "—" }
    return ml > 0 ? "+\(ml)" : String(ml)
  }

  static func fmtPts(_ p: Double) -> String {
    String(format: "%.2f", (p * 100).rounded() / 100)
  }

  /// The line a side is getting, from its own side: spread -4.5 -> home "-4.5", away "+4.5".
  static func sideLine(_ spread: Double?, side: HpSide) -> String {
    guard let s = spread, s.isFinite else { return "—" }
    let v = side == .home ? s : -s
    return v == 0 ? "PK" : v > 0 ? "+\(jsNumber(v))" : jsNumber(v)
  }

  /// Badge text for a team: its abbreviation, else initials of the city label.
  static func teamInitials(name: String, abbr: String?) -> String {
    if let abbr, !abbr.isEmpty { return String(abbr.prefix(4)).uppercased() }
    let cleaned = name.replacingOccurrences(of: #"\(.*\)"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
    let words = cleaned.split(whereSeparator: { $0.isWhitespace })
    let text = words.count > 1 ? words.compactMap { $0.first.map(String.init) }.joined() : String(name.prefix(3))
    return String(text.prefix(3)).uppercased()
  }

  /// Self-hosted team logo on the website. The one file-name exception is
  /// pro hockey's UTA, stored as utah.png.
  static func logoURL(sport: HpSport, abbr: String?) -> URL? {
    guard let abbr, !abbr.isEmpty else { return nil }
    var file = abbr.lowercased()
    if sport == .nhl && file == "uta" { file = "utah" }
    return URL(string: "\(SiteLinks.baseString)/team-logos/\(sport.logoFolder)/\(file).png")
  }

  /// Locked (no pick/unpick) once it starts or leaves "scheduled".
  static func isLocked(status: String, startTime: Date, now: Date = Date()) -> Bool {
    status != "scheduled" || startTime <= now
  }

  static func isLocked(_ g: HpGame, now: Date = Date()) -> Bool { isLocked(status: g.status, startTime: g.start_time, now: now) }

  // MARK: Weeks run Monday 00:00 -> Sunday 23:59:59 America/New_York

  static let eastern = TimeZone(identifier: "America/New_York")!

  private static var etCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = eastern
    return c
  }

  private static var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  private static func ymd(_ y: Int, _ m: Int, _ d: Int) -> String {
    String(format: "%04d-%02d-%02d", y, m, d)
  }

  private static func parseYmd(_ s: String) -> (Int, Int, Int)? {
    let p = s.split(separator: "-").compactMap { Int($0) }
    return p.count == 3 ? (p[0], p[1], p[2]) : nil
  }

  /// Plain calendar arithmetic on a YYYY-MM-DD date.
  private static func addDays(_ s: String, _ days: Int) -> String {
    guard let (y, m, d) = parseYmd(s),
          let base = utcCalendar.date(from: DateComponents(year: y, month: m, day: d)),
          let moved = utcCalendar.date(byAdding: .day, value: days, to: base)
    else { return s }
    let c = utcCalendar.dateComponents([.year, .month, .day], from: moved)
    return ymd(c.year!, c.month!, c.day!)
  }

  /// ET calendar day (YYYY-MM-DD) of an instant.
  static func etDay(_ d: Date) -> String {
    let c = etCalendar.dateComponents([.year, .month, .day], from: d)
    return ymd(c.year!, c.month!, c.day!)
  }

  /// ET date (YYYY-MM-DD) of the Monday that starts `d`'s week. Matches SQL hp_week_of.
  static func weekStartET(_ d: Date) -> String {
    let weekday = etCalendar.component(.weekday, from: d) // 1 = Sunday
    let back = (weekday + 5) % 7                          // Mon 0 ... Sun 6
    return addDays(etDay(d), -back)
  }

  /// UTC instant of 00:00 ET on a YYYY-MM-DD ET date (DST-aware).
  static func etMidnightUtc(_ s: String) -> Date {
    guard let (y, m, d) = parseYmd(s) else { return Date() }
    return etCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: 0, minute: 0)) ?? Date()
  }

  /// [start, end) bounds of the ET week starting on `weekStart`.
  static func weekBoundsUtc(_ weekStart: String) -> (start: Date, end: Date) {
    (etMidnightUtc(weekStart), etMidnightUtc(addDays(weekStart, 7)))
  }

  static func shiftWeek(_ weekStart: String, by weeks: Int) -> String { addDays(weekStart, 7 * weeks) }

  // MARK: Grading and boards

  /// Client-side grade, same rules as the hp_pick_results view.
  static func gradePick(side: HpSide, lockedMl: Int?, lockedSpread: Double?, weekStart: String,
                        sport: HpSport, status: String, winner: HpSide?, startTime: Date) -> (result: HpPickResult, points: Double) {
    if status == "postponed" || weekStartET(startTime) != weekStart { return (.void, 0) }
    if status != "final" { return (.pending, 0) }
    guard let winner else { return (.void, 0) }
    return winner == side ? (.win, pickPoints(sport: sport, lockedMl: lockedMl, lockedSpread: lockedSpread)) : (.loss, 0)
  }

  static func gradePick(_ p: HpPick, _ g: HpGame) -> (result: HpPickResult, points: Double) {
    gradePick(side: p.side, lockedMl: p.locked_ml, lockedSpread: p.locked_spread, weekStart: p.week_start,
              sport: g.sport, status: g.status, winner: g.winner, startTime: g.start_time)
  }

  struct RankInput { let userId: String; let name: String; let points: Double; let correct: Int; let bestHit: Double }

  /// Points, then correct dogs, then biggest single hit; ties share a rank.
  /// (The server ranks the real boards; this mirrors it for tests.)
  static func rankBoard(_ rows: [RankInput]) -> [(userId: String, rank: Int)] {
    let sorted = rows.sorted {
      if $0.points != $1.points { return $0.points > $1.points }
      if $0.correct != $1.correct { return $0.correct > $1.correct }
      if $0.bestHit != $1.bestHit { return $0.bestHit > $1.bestHit }
      return $0.name < $1.name
    }
    var rank = 0
    return sorted.enumerated().map { i, r in
      let prev = i > 0 ? sorted[i - 1] : nil
      if prev == nil || prev!.points != r.points || prev!.correct != r.correct || prev!.bestHit != r.bestHit { rank = i + 1 }
      return (r.userId, rank)
    }
  }

  // MARK: Errors

  /// Friendly copy for hp_* RPC error codes (HP_ERRORS on the web).
  static let errors: [String: String] = [
    "not_authenticated": "Sign in first.",
    "feature_off": "This game isn't open yet.",
    "bad_sport": "Pick basketball or hockey.",
    "bad_picks_per_week": "Underdogs per week must be 1–10.",
    "bad_name": "Group name must be 1–60 characters.",
    "too_many_leagues": "You've created the max number of groups.",
    "not_league_admin": "Only the group admin can do that.",
    "global_admin_only": "Only SUP admins can change the global group.",
    "league_not_found": "Group not found.",
    "week_in_progress": "Underdogs per week can't change once someone has picked this week. Try again next Monday.",
    "bad_code": "No group with that code.",
    "league_full": "That group is full.",
    "not_member": "Join the group first.",
    "game_not_found": "Game not found.",
    "wrong_sport": "That game isn't in this group's sport.",
    "game_locked": "That game has started. Picks are locked.",
    "no_odds": "No line yet for that game.",
    "no_spread": "No point spread yet for that game.",
    "odds_stale": "The line for that game is out of date. Try again after the next sync.",
    "no_underdog": "That's a pick'em line, so there's no underdog to take.",
    "not_underdog": "You can only pick the underdog.",
    "already_picked": "You already have that dog.",
    "weekly_limit": "You've used all your picks this week.",
    "not_found_or_locked": "That pick is locked (game started) or already gone.",
  ]

  static func errorMessage(_ raw: String?) -> String {
    let m = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if let hit = errors[m] { return hit }
    // Whole-word match inside a longer message ("ERROR: weekly_limit ...").
    for (code, copy) in errors where m.range(of: "\\b\(code)\\b", options: .regularExpression) != nil {
      return copy
    }
    return m.isEmpty ? "Something went wrong." : m
  }
}

/// A number the way JavaScript prints it: 3 not 3.0, 4.5 stays 4.5.
func jsNumber(_ v: Double) -> String {
  if v == v.rounded() && abs(v) < 1e15 { return String(format: "%.0f", v) }
  var s = String(format: "%.6f", v)
  while s.hasSuffix("0") { s.removeLast() }
  if s.hasSuffix(".") { s.removeLast() }
  return s
}
