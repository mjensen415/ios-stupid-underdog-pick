import Foundation

// "Where to watch" (SUP Pro): turn a network name from game_broadcasts into
// a link. ESPN's own networks get a per-game link (ESPN's game page, which
// carries the Watch button); everything else goes to the network's live /
// sports page. Local and regional channels have no reliable link, so they
// show as a name only. Port of the web's src/lib/watchLinks.ts (keep in sync).
//
// Links are plain https URLs opened with openURL, so the ESPN / Peacock /
// network app takes over as a universal link when it's installed. No
// private URL schemes, no network logos, no affiliate links.

enum WatchSport: String {
  case cfb, nfl, nba, nhl

  var espnPath: String {
    switch self {
    case .cfb: return "college-football"
    case .nfl: return "nfl"
    case .nba: return "nba"
    case .nhl: return "nhl"
    }
  }
}

struct BroadcastNetwork: Decodable, Equatable {
  let name: String
  /// "TV" or "Streaming"
  let kind: String?
  /// "National", "Home", "Away"
  let market: String?
}

struct WatchLink: Equatable {
  let label: String
  let url: URL?
  /// ESPN game page (per-game deep link).
  let deep: Bool
  let local: Bool
}

enum WatchLinks {
  static func espnGameURL(sport: WatchSport, eventId: String) -> URL? {
    URL(string: "https://www.espn.com/\(sport.espnPath)/game/_/gameId/\(eventId)")
  }

  static let espnFamily: Set<String> = [
    "ESPN", "ESPN2", "ESPNU", "ESPNEWS", "ESPN+", "ABC", "SEC Network", "SEC Network+", "SECN", "SECN+",
    "ACC Network", "ACCN", "ACCNX", "ACC Network Extra", "LHN", "Longhorn Network", "ESPN Deportes",
  ]

  /// Network -> its own live / sports page. Keys are ESPN's short names.
  static let networkURL: [String: String] = [
    "Fox": "https://www.foxsports.com/live",
    "FOX": "https://www.foxsports.com/live",
    "FS1": "https://www.foxsports.com/live",
    "FS2": "https://www.foxsports.com/live",
    "BTN": "https://www.foxsports.com/live",
    "Big Ten Network": "https://www.foxsports.com/live",
    "B1G+": "https://www.bigtenplus.com",
    "CBS": "https://www.paramountplus.com/live-tv/",
    "CBSSN": "https://www.cbssports.com/cbs-sports-network/",
    "Paramount+": "https://www.paramountplus.com/live-tv/",
    "NBC": "https://www.peacocktv.com/sports",
    "Peacock": "https://www.peacocktv.com/sports",
    "USA Net": "https://www.usanetwork.com/live",
    "USA Network": "https://www.usanetwork.com/live",
    "TNT": "https://www.hbomax.com/sports",
    "truTV": "https://www.hbomax.com/sports",
    "TBS": "https://www.hbomax.com/sports",
    "Max": "https://www.hbomax.com/sports",
    "HBO Max": "https://www.hbomax.com/sports",
    "CW": "https://www.cwtv.com/live/",
    "The CW": "https://www.cwtv.com/live/",
    "Prime Video": "https://www.primevideo.com/",
    "Prime Video (Local)": "https://www.primevideo.com/",
    "Netflix": "https://www.netflix.com/",
    "NFL Net": "https://www.nfl.com/plus/",
    "NFL Network": "https://www.nfl.com/plus/",
    "NFL+": "https://www.nfl.com/plus/",
    "NBA TV": "https://www.nba.com/watch",
    "NBA League Pass": "https://www.nba.com/watch/league-pass-stream",
    "NHL Network": "https://www.nhl.com/tv",
    "Disney+": "https://www.disneyplus.com/",
    "Hulu": "https://www.hulu.com/live-tv",
    "YouTube": "https://tv.youtube.com/",
    "MW+": "https://www.themw.com/watch/",
  ]

  static func link(sport: WatchSport, eventId: String, network n: BroadcastNetwork) -> WatchLink {
    if espnFamily.contains(n.name) {
      return WatchLink(label: n.name, url: espnGameURL(sport: sport, eventId: eventId), deep: true, local: false)
    }
    let url = networkURL[n.name].flatMap(URL.init(string:))
    return WatchLink(label: n.name, url: url, deep: false, local: url == nil && n.market != "National")
  }

  /// Links worth showing, national first; channels without a link are
  /// dropped unless nothing else exists. At most 3.
  static func links(sport: WatchSport, eventId: String, networks: [BroadcastNetwork]) -> [WatchLink] {
    let all = networks.map { link(sport: sport, eventId: eventId, network: $0) }
    let linked = all.filter { $0.url != nil }
    return Array((linked.isEmpty ? all : linked).prefix(3))
  }

  /// The one capsule a game row shows (layout A): the first linked network.
  static func primary(sport: WatchSport, eventId: String, networks: [BroadcastNetwork]) -> WatchLink? {
    links(sport: sport, eventId: eventId, networks: networks).first { $0.url != nil }
  }
}
