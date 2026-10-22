import Foundation

// "Global" groups: the catch-all group everyone is in without creating one.
// Native port of the web's src/lib/globalGroups.ts (keep in sync).
//
// - CFB Underdog, Pro Ball Underdog and Pickems: picks made without a group
//   already score on the site-wide standings. Those standings ARE the global
//   group, so there are no rows for it; the UI just shows them as a
//   "Global · everyone" card.
// - Hoops and Pucks: picks only exist inside an hp_leagues row, so each sport
//   has one real league with is_global = true ("Global Hoops" / "Global
//   Pucks"): 5 dogs a week, Mon-Sun ET, open to everyone, joined with one tap
//   (hp_join_global), never deleted on leave, site-admin-only edits.

enum GlobalGroups {
  static let tagline = "Global: everyone who plays. No group needed."
  static let joinCTA = "Join the global group, it's free"
  static let picksPerWeek = 5
  static let title = "Global · everyone"

  /// Label for a game's global board.
  static func label(_ game: CurrentGame) -> String {
    switch game {
    case .cfb: return "CFB Underdog"
    case .nfl: return "Pro Ball Underdog"
    case .pickems: return "Pickems"
    }
  }

  // MARK: Hoops / Pucks leagues

  /// Global first, then the rest in their original order.
  static func orderHpLeagues(_ list: [HpLeague]) -> [HpLeague] {
    list.filter(\.is_global) + list.filter { !$0.is_global }
  }

  /// Your leagues for one sport, plus that sport's global league even when
  /// you haven't joined it yet (role nil), so it can be shown as the default.
  static func buildHpLeagueList(mine: [HpLeague], global: HpLeague?, sport: HpSport) -> [HpLeague] {
    let sportMine = mine.filter { $0.sport == sport }
    guard var g = global, g.sport == sport, !sportMine.contains(where: { $0.id == g.id }) else {
      return orderHpLeagues(sportMine)
    }
    g.role = nil
    return orderHpLeagues(sportMine + [g])
  }

  /// Which league the page opens on: the one asked for if listed, else the
  /// first one you're a member of (Global first), else the global league.
  static func pickDefaultHpLeague(_ list: [HpLeague], requested: UUID?) -> HpLeague? {
    if let requested, let asked = list.first(where: { $0.id == requested }) { return asked }
    return list.first(where: \.isMember) ?? list.first(where: \.is_global) ?? list.first
  }

  /// Tapping a dog in this league needs a join first (one tap: join, then pick).
  static func needsGlobalJoin(_ league: HpLeague?) -> Bool {
    guard let league else { return false }
    return league.is_global && !league.isMember
  }

  /// Only site admins edit a global league; league admins edit their own.
  static func canEdit(_ league: HpLeague?, isSiteAdmin: Bool) -> Bool {
    guard let league else { return false }
    return league.is_global ? isSiteAdmin : league.isAdmin
  }
}
