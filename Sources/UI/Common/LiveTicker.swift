import SwiftUI
import Supabase

// Live-games ticker (round 3) -- native take on the web's TopStrip
// LiveTicker (src/components/TopStrip.tsx + src/lib/topStrip.ts). Unlike the
// web strip it lists every live game the player can see, not only upsets;
// games where the underdog is ahead get the pulsing red live dot and bold
// text. Slow marquee; with Reduce Motion it's a static row you can scroll.
// Hidden entirely when nothing is live. Reads existing tables only
// (v_games_named for CFB / Pro Ball, daily_games for Hoops / Pucks).

struct LiveTickerItem: Identifiable, Equatable {
  enum Sport: String { case cfb, nfl, nba, nhl }
  let id: UUID
  let sport: Sport
  let week: Int?
  let text: String
  /// The underdog is ahead right now.
  let dogLeads: Bool
  /// Kickoff, for ordering.
  var start: Date = .distantPast
  /// Has a line (spread, or moneylines for Pucks).
  var hasLine: Bool = true

  /// One live game -> one item. Spreads are home-relative (positive = home
  /// is the dog); Pucks uses moneylines (dog = plus money). With no line:
  /// "Away 14 @ Home 10".
  static func make(id: UUID, sport: Sport, week: Int?, home: String, away: String,
                   homeScore: Int?, awayScore: Int?, spread: Double?, homeMl: Double? = nil, awayMl: Double? = nil,
                   detail: String? = nil) -> LiveTickerItem {
    let h = homeScore ?? 0, a = awayScore ?? 0
    var dogHome: Bool?
    var line = ""
    if sport == .nhl {
      if let hm = homeMl, let am = awayMl, hm != am {
        dogHome = hm > am
        line = "+\(Int((dogHome! ? hm : am).rounded()))"
      }
    } else if let s = spread, s != 0 {
      dogHome = s > 0
      line = "+\(jsNumber(abs(s)))"
    }
    let tail = detail.map { $0.isEmpty ? "" : " · \($0)" } ?? ""
    guard let dogHome else {
      return LiveTickerItem(id: id, sport: sport, week: week,
                            text: "\(shortTeam(away)) \(a) @ \(shortTeam(home)) \(h)\(tail)", dogLeads: false)
    }
    let dog = shortTeam(dogHome ? home : away), fav = shortTeam(dogHome ? away : home)
    let ds = dogHome ? h : a, fs = dogHome ? a : h
    return LiveTickerItem(id: id, sport: sport, week: week,
                          text: "\(dog) \(line) \(ds) · \(fav) \(fs)\(tail)", dogLeads: ds > fs)
  }

  /// "Missouri State" -> "Missouri St" (web's shortTeam).
  static func shortTeam(_ name: String) -> String {
    let n = name.trimmingCharacters(in: .whitespaces)
    if n.isEmpty { return "TBD" }
    return n.replacingOccurrences(of: #"\bState\b"#, with: "St", options: .regularExpression)
  }
}

@MainActor
final class LiveTickerModel: ObservableObject {
  @Published var items: [LiveTickerItem] = []

  func load(client: SupabaseClient, hoops: Bool, pucks: Bool) async {
    struct FB: Decodable {
      let id: UUID; let sport: String; let week: Int?; let start_time: Date
      let home_name: String?; let away_name: String?
      let home_short: String?; let away_short: String?
      let home_points: Int?; let away_points: Int?; let latest_spread: Double?
    }
    struct Daily: Decodable {
      let id: UUID; let sport: String; let status_detail: String?; let start_time: Date
      let home_name: String?; let away_name: String?
      let home_score: Int?; let away_score: Int?
      let spread: Double?; let home_ml: Double?; let away_ml: Double?
    }
    var out: [LiveTickerItem] = []
    // Short-name columns may not exist on every backend; fall back without.
    let base = "id, sport, week, start_time, home_name, away_name, home_points, away_points, latest_spread"
    var fbData: Data?
    for cols in [base + ", home_short, away_short", base] {
      if let res = try? await client.from("v_games_named").select(cols)
        // Lined games only: most live Saturday CFB games are lower
        // divisions with no spread, and they aren't on the Games screen.
        .eq("status", value: "in_progress").in("sport", values: ["cfb", "nfl"])
        .not("latest_spread", operator: .is, value: "null")
        .order("start_time", ascending: true).limit(60).execute() {
        fbData = res.data; break
      }
    }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withFallback
    if let fbData, let rows = try? dec.decode([FB].self, from: fbData) {
      out += rows.map { g in
        var it = LiveTickerItem.make(id: g.id, sport: g.sport == "nfl" ? .nfl : .cfb, week: g.week,
                                     home: g.home_short ?? g.home_name ?? "Home", away: g.away_short ?? g.away_name ?? "Away",
                                     homeScore: g.home_points, awayScore: g.away_points, spread: g.latest_spread)
        it.start = g.start_time
        return it
      }
    }
    let daily = [hoops ? "nba" : nil, pucks ? "nhl" : nil].compactMap { $0 }
    if !daily.isEmpty,
       let res = try? await client.from("daily_games")
        .select("id, sport, start_time, status_detail, home_name, away_name, home_score, away_score, spread, home_ml, away_ml")
        .eq("status", value: "in_progress").in("sport", values: daily).limit(60).execute(),
       let rows = try? dec.decode([Daily].self, from: res.data) {
      out += rows.compactMap { g in
        let lined = g.sport == "nhl" ? (g.home_ml != nil && g.away_ml != nil) : g.spread != nil
        guard lined else { return nil }
        var it = LiveTickerItem.make(id: g.id, sport: g.sport == "nhl" ? .nhl : .nba, week: nil,
                                     home: g.home_name ?? "Home", away: g.away_name ?? "Away",
                                     homeScore: g.home_score, awayScore: g.away_score, spread: g.spread,
                                     homeMl: g.home_ml, awayMl: g.away_ml, detail: g.status_detail)
        it.start = g.start_time
        return it
      }
    }
    // By kickoff, capped so the marquee stays readable.
    items = Array(out.sorted { ($0.start, $0.text) < ($1.start, $1.text) }.prefix(30))
  }
}

/// The slim strip. Loads itself and refreshes every 60s while on screen.
struct LiveTickerStrip: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject private var appState: AppState
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  @StateObject private var model = LiveTickerModel()
  /// Optional override for previews / snapshot tests.
  var items: [LiveTickerItem]? = nil
  /// Space above the strip, only when it shows.
  var topPadding: CGFloat = 0

  var body: some View {
    let shown = items ?? model.items
    Group {
      if !shown.isEmpty {
        LiveTickerBar(items: shown) { open($0) }
          .padding(.top, topPadding)
      }
    }
    .task {
      guard items == nil, let client else { return }
      while !Task.isCancelled {
        await model.load(client: client,
                         hoops: featureFlags.isVisible(HpSport.nba.flag),
                         pucks: featureFlags.isVisible(HpSport.nhl.flag))
        try? await Task.sleep(nanoseconds: 60_000_000_000)
      }
    }
  }

  /// Jump to the game: Games tab on its sport and week, scrolled to it.
  private func open(_ item: LiveTickerItem) {
    switch item.sport {
    case .cfb, .nfl:
      appState.requestedGame = .init(id: item.id, sport: item.sport.rawValue, week: item.week)
      appState.goToUnderdog(sport: item.sport.rawValue)
    case .nba: appState.goToHoopsPucks(.nba)
    case .nhl: appState.goToHoopsPucks(.nhl)
    }
  }
}

/// Visual part: red "Live" tag + pulsing dot, then the items.
struct LiveTickerBar: View {
  let items: [LiveTickerItem]
  /// Static row regardless of the setting (snapshot tests).
  var forceStatic = false
  let onTap: (LiveTickerItem) -> Void
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  private var reduceMotion: Bool { systemReduceMotion || forceStatic }
  @State private var contentWidth: CGFloat = 0
  @State private var start = Date()

  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: 6) {
        PulseDot(animate: !reduceMotion)
        Text("Live").font(BoldTheme.Fonts.body(13, weight: .bold)).foregroundColor(SUPColors.liveRed)
      }
      .padding(.leading, 12).padding(.trailing, 10)
      .frame(maxHeight: .infinity)
      .overlay(alignment: .trailing) { Rectangle().fill(BoldTheme.Colors.border).frame(width: 1) }

      if reduceMotion || items.count < 2 {
        ScrollView(.horizontal, showsIndicators: false) { row.padding(.trailing, 12) }
      } else {
        GeometryReader { geo in
          TimelineView(.animation) { tl in
            // ~30pt/s: slow and readable.
            let w = max(contentWidth, 1)
            let x = -CGFloat(tl.date.timeIntervalSince(start) * 30).truncatingRemainder(dividingBy: w)
            HStack(spacing: 0) { row; row }
              .fixedSize()
              .offset(x: x)
          }
          .frame(width: geo.size.width, alignment: .leading)
          .clipped()
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                     .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
      }
    }
    .frame(height: 36)
    .background(Capsule().fill(BoldTheme.Colors.card))
    .clipShape(Capsule())
    // Short label: "Live games, 12", not every score read out.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Live games, \(items.count)")
    .accessibilityHint("Shows live scores. Open Games to see them all.")
  }

  private var row: some View {
    HStack(spacing: 0) {
      ForEach(items) { it in
        Button { onTap(it) } label: {
          HStack(spacing: 6) {
            if it.dogLeads { PulseDot(animate: !reduceMotion, size: 6) }
            Text(verbatim: it.text)
              .font(BoldTheme.Fonts.body(13, weight: it.dogLeads ? .bold : .medium))
              .foregroundColor(it.dogLeads ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
              .lineLimit(1)
              .fixedSize()
          }
          .padding(.leading, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(it.text + (it.dogLeads ? ", underdog leads" : ""))
        Text("·").foregroundColor(BoldTheme.Colors.textFaint).padding(.leading, 14)
      }
    }
    .background(GeometryReader { g in Color.clear.onAppear { contentWidth = g.size.width }
      .onChange(of: g.size.width) { _, w in contentWidth = w } })
  }
}

private struct PulseDot: View {
  var animate: Bool
  var size: CGFloat = 7
  @State private var dim = false
  var body: some View {
    Circle().fill(SUPColors.liveRed).frame(width: size, height: size)
      .opacity(dim ? 0.35 : 1)
      .onAppear {
        guard animate else { return }
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true }
      }
  }
}
