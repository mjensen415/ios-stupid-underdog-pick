import SwiftUI
import Supabase

// Underdog Board (SUP Pro), read-only, simplified for iOS. On the web
// (ProBoard.tsx + lib/proBoard.ts) the model win %, blend, expected points
// and tags are computed in the browser from conference tiers. iOS shows only
// what's simple and comes straight from the data: every lined CFB dog this
// week by its line, with the prediction market's win chance and line value
// from market_latest when there's a snapshot. Not betting advice.

struct BoardDog: Identifiable, Equatable {
  let id: UUID
  let dog: String
  let opp: String
  let homeDog: Bool
  let line: Double
  let startTime: Date
  /// Market chance the dog wins outright (0-1), nil without a snapshot.
  let market: Double?
  /// Positive = SUP pays more points than the market thinks the dog needs.
  let lineValue: Double?

  /// From a home-relative spread and the market snapshot. The snapshot names
  /// its own dog; if it disagrees with ours, flip its numbers to our side
  /// (same as buildRow in the web's proBoard.ts). Nil for pick'em / no line.
  static func make(id: UUID, home: String, away: String, spread: Double?, startTime: Date,
                   marketDogTeam: String?, marketDogWin: Double?, marketFairSpread: Double?) -> BoardDog? {
    guard let spread, spread.isFinite, spread != 0 else { return nil }
    let homeDog = spread > 0
    let dog = homeDog ? home : away
    let opp = homeDog ? away : home
    var market: Double? = nil
    var fair: Double? = nil
    if let w = marketDogWin {
      let flip = marketDogTeam != nil && marketDogTeam != dog && marketDogTeam == opp
      market = flip ? 1 - w : w
      if let f = marketFairSpread { fair = flip ? -f : f }
    }
    let line = abs(spread)
    return BoardDog(id: id, dog: dog, opp: opp, homeDog: homeDog, line: line, startTime: startTime,
                    market: market, lineValue: fair.map { line - $0 })
  }
}

struct UnderdogBoardView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  @EnvironmentObject private var pro: ProStore

  private enum Sort: Hashable { case line, market, kickoff }
  @State private var rows: [BoardDog] = []
  @State private var week: Int?
  @State private var loaded = false
  @State private var sort: Sort = .line

  private var isPro: Bool { pro.isPro(admin: featureFlags.isAdmin) }

  private var sorted: [BoardDog] {
    switch sort {
    case .line: return rows.sorted { $0.line > $1.line }
    case .market: return rows.sorted { ($0.market ?? -1) > ($1.market ?? -1) }
    case .kickoff: return rows.sorted { $0.startTime < $1.startTime }
    }
  }

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 4) {
            Text("SUP PRO · CFB\(week.map { " · WEEK \(formatWeekLabel($0))" } ?? "")")
              .font(BoldTheme.Fonts.mono(10.5, weight: .bold)).tracking(1).foregroundColor(BoldTheme.Colors.green)
            Text("UNDERDOG BOARD").font(BoldTheme.Fonts.display(40)).foregroundColor(BoldTheme.Colors.text)
            Text("Every lined dog this week. Market = the prediction market's chance the dog wins outright. Value = points SUP pays beyond the market's fair line.")
              .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
              .fixedSize(horizontal: false, vertical: true)
          }
          if !isPro {
            ProToolsTeaser()
          } else {
            PillToggle(options: [(label: "Line", value: Sort.line), (label: "Market %", value: .market), (label: "Kickoff", value: .kickoff)],
                       selection: $sort)
            if !loaded {
              ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
            } else if rows.isEmpty {
              Text("No lined games left this week.").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim)
            } else {
              VStack(spacing: 0) {
                ForEach(sorted) { r in
                  row(r)
                  if r.id != sorted.last?.id { Divider().overlay(BoldTheme.Colors.border) }
                }
              }
              .padding(.horizontal, 12)
              .background(RoundedRectangle(cornerRadius: 16).fill(BoldTheme.Colors.glassStrong))
            }
          }
          Text("Not betting advice. Lines and market numbers are for info only; SUP scoring only counts outright wins.")
            .font(BoldTheme.Fonts.body(11)).foregroundColor(BoldTheme.Colors.textFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
      }
    }
    .navigationTitle("Underdog Board")
    .navigationBarTitleDisplayMode(.inline)
    .task { if isPro { await load() } }
  }

  private func row(_ r: BoardDog) -> some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(r.dog).font(BoldTheme.Fonts.body(14, weight: .bold)).foregroundColor(BoldTheme.Colors.text).lineLimit(1)
        Text("\(r.homeDog ? "vs" : "@") \(r.opp) · \(kickoff(r.startTime))")
          .font(BoldTheme.Fonts.body(11.5)).foregroundColor(BoldTheme.Colors.textDim).lineLimit(1)
      }
      Spacer(minLength: 6)
      Text("+\(jsNumber(r.line))").font(BoldTheme.Fonts.display(22)).foregroundColor(BoldTheme.Colors.goldDeep)
        .frame(minWidth: 46, alignment: .trailing)
      VStack(alignment: .trailing, spacing: 1) {
        Text(r.market.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
          .font(BoldTheme.Fonts.mono(12, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
        Text(r.lineValue.map { v in let x = (v * 10).rounded() / 10; return x == 0 ? "0.0" : (x > 0 ? "+" : "") + String(format: "%.1f", x) } ?? "—")
          .font(BoldTheme.Fonts.mono(10.5))
          .foregroundColor((r.lineValue ?? 0) > 0 ? BoldTheme.Colors.green : BoldTheme.Colors.textFaint)
      }
      .frame(minWidth: 48, alignment: .trailing)
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private func kickoff(_ d: Date) -> String {
    let f = DateFormatter()
    f.timeZone = HP.eastern
    f.dateFormat = "EEE h:mm a"
    return f.string(from: d) + " ET"
  }

  private func load() async {
    defer { loaded = true }
    guard let client, let ctx = try? await ContextService(client: client).getCurrentContext(sport: "cfb") else { return }
    week = ctx.week
    // Raw games rows (school names, as the web board uses): market_latest
    // names its dog with the same games.home_team / away_team strings.
    struct G: Decodable { let id: UUID; let home_team: String?; let away_team: String?; let latest_spread: Double?; let status: String?; let start_time: Date }
    struct M: Decodable { let game_id: UUID; let dog_team: String?; let market_dog_win: Double?; let market_fair_spread: Double? }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withFallback
    guard let res = try? await client.from("games")
      .select("id, home_team, away_team, latest_spread, status, start_time")
      .eq("season", value: ctx.season).eq("week", value: ctx.week).eq("sport", value: "cfb")
      .neq("status", value: "final")
      .order("start_time", ascending: true).execute(),
      let games = try? dec.decode([G].self, from: res.data) else { return }
    let lined = games.filter { ($0.latest_spread ?? 0) != 0 }
    var market: [UUID: M] = [:]
    if !lined.isEmpty,
       let mres = try? await client.from("market_latest").select("game_id, dog_team, market_dog_win, market_fair_spread")
        .in("game_id", values: lined.map(\.id)).execute(),
       let ms = try? dec.decode([M].self, from: mres.data) {
      market = Dictionary(ms.map { ($0.game_id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    rows = lined.compactMap { g in
      let m = market[g.id]
      return BoardDog.make(id: g.id, home: g.home_team ?? "Home", away: g.away_team ?? "Away", spread: g.latest_spread,
                           startTime: g.start_time, marketDogTeam: m?.dog_team, marketDogWin: m?.market_dog_win,
                           marketFairSpread: m?.market_fair_spread)
    }
  }
}
