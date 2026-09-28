import SwiftUI
import Supabase

// My Picks, one section per contest (CFB / Pro Ball / Pickems):
//   - "This week" hero card: current pick + live status + pick/change CTA
//   - season stat strip (record, points banked, hit rate / accuracy)
//   - week-by-week history timeline
// Replaces the old flat ledger that mixed every sport's Underdog picks in
// one list and never showed Pickems history at all.

// MARK: - Models

struct UnderdogWeekEntry: Identifiable {
  let pick: Pick
  let game: Game
  var id: UUID { pick.id }

  var pickedIsHome: Bool { pick.picked_team_id == game.homeTeamId }
  var pickedName: String { (pickedIsHome ? game.homeTeam : game.awayTeam) ?? "Your pick" }
  var opponentName: String { (pickedIsHome ? game.awayTeam : game.homeTeam) ?? "Opponent" }
  var spread: Double? { pick.picked_team_id == game.derivedUnderdogTeamId ? game.underdogSpread : nil }
  var outcome: Game.PickOutcome { game.outcome(forPickedTeamId: pick.picked_team_id) }
  /// Underdog must win outright -- points = the spread.
  var points: Double { outcome == .win ? (spread ?? 0) : 0 }
  var isLive: Bool { game.status == "in_progress" }

  /// "24–21" from the picked team's side.
  var scoreLine: String? {
    guard let h = game.homePoints, let a = game.awayPoints, game.status == "final" || isLive else { return nil }
    return pickedIsHome ? "\(h)–\(a)" : "\(a)–\(h)"
  }
}

struct PickemsWeekEntry: Identifiable {
  let season: Int
  let week: Int
  let picked: Int
  let correct: Int
  let decided: Int
  var id: String { "\(season)-\(week)" }
}

enum MyPicksSection: Hashable { case cfb, nfl, pickems }

// MARK: - View model

@MainActor
final class MyPicksViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published var loaded = false

  @Published var underdog: [UnderdogWeekEntry] = []
  @Published var pickemsWeeks: [PickemsWeekEntry] = []
  @Published var logoMap: [UUID: URL] = [:]

  @Published var cfbContext: CurrentContext?
  @Published var nflContext: CurrentContext?
  /// Whether any pickable game (has a line, not kicked off) remains this week.
  @Published var underdogOpen: [String: Bool] = [:]

  // Pickems current week
  @Published var pickemsThisWeekTotal = 0
  @Published var pickemsThisWeekPicked = 0
  @Published var pickemsThisWeekCorrect = 0
  @Published var pickemsThisWeekWrong = 0
  @Published var pickemsThisWeekOpen = 0
  @Published var pickemsThisWeekUnfinished = 0

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  func load() async {
    guard let client else { errorText = "No client"; return }
    isLoading = true
    errorText = nil
    defer { isLoading = false; loaded = true }
    do {
      let userId = try await client.auth.session.user.id
      async let cfbCtx = try? ContextService(client: client).getCurrentContext(sport: "cfb")
      async let nflCtx = try? ContextService(client: client).getCurrentContext(sport: "nfl")
      cfbContext = await cfbCtx
      nflContext = await nflCtx

      async let underdogTask: Void = loadUnderdog(client: client, userId: userId)
      async let pickemsTask: Void = loadPickems(client: client, userId: userId)
      try await underdogTask
      try await pickemsTask

      // Logos only for teams actually shown (picked teams), not all teams.
      let teamIds = Array(Set(underdog.map(\.pick.picked_team_id)))
      if !teamIds.isEmpty {
        struct T: Decodable { let id: UUID; let logo_url: String? }
        let teamRes = try await client.from("teams").select("id, logo_url").in("id", values: teamIds).execute()
        let teams = try JSONDecoder().decode([T].self, from: teamRes.data)
        logoMap = Dictionary(uniqueKeysWithValues: teams.map { t in (t.id, t.logo_url.flatMap { URL(string: $0) }) }).compactMapValues { $0 }
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private var dateDecoder: JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601withFallback
    return d
  }

  private func loadUnderdog(client: SupabaseClient, userId: UUID) async throws {
    // Shared picks only (group_id IS NULL) -- per-group overrides would
    // otherwise show the same week twice.
    let res = try await client
      .from("picks")
      .select("id, user_id, game_id, picked_team_id, season, week, created_at")
      .eq("user_id", value: userId)
      .is("group_id", value: nil)
      .execute()
    let picks = try JSONDecoder().decode([Pick].self, from: res.data)

    var gamesById: [UUID: Game] = [:]
    let ids = Array(Set(picks.map(\.game_id)))
    if !ids.isEmpty {
      let gRes = try await client
        .from("v_games_named")
        .select("id, season, week, status, home_name, away_name, home_team_id, away_team_id, favorite_team_id, start_time, betting_line, latest_spread, picks_locked, home_points, away_points, sport")
        .in("id", values: ids)
        .execute()
      let games = try dateDecoder.decode([Game].self, from: gRes.data)
      gamesById = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
    }
    underdog = picks.compactMap { p in gamesById[p.game_id].map { UnderdogWeekEntry(pick: p, game: $0) } }

    // Is anything still pickable this week? Drives "Pick now" vs "Missed".
    func anyOpen(_ ctx: CurrentContext?, _ sport: String) async -> Bool {
      guard let ctx else { return false }
      let games = (try? await GamesService(client: client).fetch(season: ctx.season, week: ctx.week, sport: sport)) ?? []
      return games.contains { $0.latestSpread != nil && $0.startTime > Date() && $0.picksLocked != true }
    }
    async let cfbOpen = anyOpen(cfbContext, "cfb")
    async let nflOpen = anyOpen(nflContext, "nfl")
    underdogOpen = ["cfb": await cfbOpen, "nfl": await nflOpen]
  }

  private func loadPickems(client: SupabaseClient, userId: UUID) async throws {
    struct Row: Decodable { let game_id: UUID; let picked_team_id: UUID; let acting_as_profile_id: UUID? }
    let res = try await client
      .from("pickems_picks")
      .select("game_id, picked_team_id, acting_as_profile_id")
      .eq("user_id", value: userId)
      .is("group_id", value: nil)
      .execute()
    let rows = try JSONDecoder().decode([Row].self, from: res.data).filter { $0.acting_as_profile_id == nil }
    let pickByGame = Dictionary(rows.map { ($0.game_id, $0.picked_team_id) }, uniquingKeysWith: { a, _ in a })

    struct G: Decodable {
      let id: UUID; let season: Int; let week: Int; let status: String
      let home_team_id: UUID; let away_team_id: UUID; let home_points: Int?; let away_points: Int?
      let start_time: Date
      var winner: UUID? {
        guard status == "final", let h = home_points, let a = away_points, h != a else { return nil }
        return h > a ? home_team_id : away_team_id
      }
    }
    var games: [G] = []
    if !pickByGame.isEmpty {
      let gRes = try await client
        .from("v_games_named")
        .select("id, season, week, status, home_team_id, away_team_id, home_points, away_points, start_time")
        .in("id", values: Array(pickByGame.keys))
        .execute()
      games = try dateDecoder.decode([G].self, from: gRes.data)
    }

    var byWeek: [String: (season: Int, week: Int, picked: Int, correct: Int, decided: Int)] = [:]
    for g in games {
      let key = "\(g.season)-\(g.week)"
      var e = byWeek[key] ?? (g.season, g.week, 0, 0, 0)
      e.picked += 1
      if let w = g.winner {
        e.decided += 1
        if pickByGame[g.id] == w { e.correct += 1 }
      }
      byWeek[key] = e
    }
    pickemsWeeks = byWeek.values
      .map { PickemsWeekEntry(season: $0.season, week: $0.week, picked: $0.picked, correct: $0.correct, decided: $0.decided) }
      .sorted { ($0.season, $0.week) > ($1.season, $1.week) }

    // Current week: every game, not just picked ones.
    pickemsThisWeekTotal = 0; pickemsThisWeekPicked = 0; pickemsThisWeekUnfinished = 0
    pickemsThisWeekCorrect = 0; pickemsThisWeekWrong = 0; pickemsThisWeekOpen = 0
    guard let ctx = nflContext else { return }
    let weekGames = (try? await PickemsService(client: client).fetchGames(season: ctx.season, week: ctx.week, sport: "nfl")) ?? []
    pickemsThisWeekTotal = weekGames.count
    pickemsThisWeekOpen = weekGames.filter { !$0.isLocked }.count
    pickemsThisWeekUnfinished = weekGames.filter { !$0.isFinal }.count
    for g in weekGames {
      guard let picked = pickByGame[g.id] else { continue }
      pickemsThisWeekPicked += 1
      if let w = g.winnerTeamId { if w == picked { pickemsThisWeekCorrect += 1 } else { pickemsThisWeekWrong += 1 } }
    }
  }
}

// MARK: - View

struct MyPicksView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject private var appState: AppState
  @StateObject private var viewModel = MyPicksViewModel()
  @State private var selectedSeason: Int?

  private var section: MyPicksSection {
    switch appState.currentGame {
    case .cfb: return .cfb
    case .nfl: return .nfl
    case .pickems: return .pickems
    }
  }

  private var sectionBinding: Binding<MyPicksSection> {
    Binding(
      get: { section },
      set: { new in
        switch new {
        case .cfb: appState.currentGame = .cfb
        case .nfl: appState.currentGame = .nfl
        case .pickems: appState.currentGame = .pickems
        }
      }
    )
  }

  private var sport: String { section == .nfl ? "nfl" : "cfb" }
  private var context: CurrentContext? { section == .cfb ? viewModel.cfbContext : viewModel.nflContext }

  // MARK: Season scoping

  private var availableSeasons: [Int] {
    let seasons: [Int]
    if section == .pickems {
      seasons = viewModel.pickemsWeeks.map(\.season)
    } else {
      seasons = viewModel.underdog.filter { $0.game.sport == sport }.map(\.pick.season)
    }
    var set = Set(seasons)
    if let s = context?.season { set.insert(s) }
    return set.sorted(by: >)
  }

  private var season: Int? { selectedSeason ?? context?.season ?? availableSeasons.first }

  private var sportEntries: [UnderdogWeekEntry] {
    viewModel.underdog.filter { $0.game.sport == sport && $0.pick.season == season }
  }

  private var thisWeekEntry: UnderdogWeekEntry? {
    guard let ctx = context, season == ctx.season else { return nil }
    return sportEntries.first { $0.pick.week == ctx.week }
  }

  private var historyEntries: [UnderdogWeekEntry] {
    sportEntries
      .filter { !(season == context?.season && $0.pick.week == context?.week) }
      .sorted { $0.pick.week > $1.pick.week }
  }

  private var pickemsHistory: [PickemsWeekEntry] {
    viewModel.pickemsWeeks.filter {
      $0.season == season && !($0.season == viewModel.nflContext?.season && $0.week == viewModel.nflContext?.week)
    }
  }

  // MARK: Body

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()
        BoldTheme.AmbientBlobs().ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            header
            sectionToggle

            if let e = viewModel.errorText {
              errorState(e)
            } else if !viewModel.loaded {
              ProgressView().tint(BoldTheme.Colors.goldDeep)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else if section == .pickems {
              pickemsSection
            } else {
              underdogSection
            }
          }
          .padding(.horizontal, 18)
          .padding(.top, 8)
          .padding(.bottom, 32)
        }
        .refreshable { await viewModel.load() }
      }
      .navigationBarHidden(true)
    }
    .task {
      if let client {
        viewModel.configure(client: client)
        await viewModel.load()
      }
    }
    .onChange(of: appState.currentGame) { _, _ in selectedSeason = nil }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("MY PICKS")
        .font(BoldTheme.Fonts.display(26))
        .tracking(0.6)
        .foregroundColor(BoldTheme.Colors.text)
      Spacer()
      if availableSeasons.count > 1 {
        Menu {
          ForEach(availableSeasons, id: \.self) { s in
            Button(String(s)) { selectedSeason = s }
          }
        } label: {
          HStack(spacing: 4) {
            Text(verbatim: "\(season ?? 0)")
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
          }
          .font(BoldTheme.Fonts.body(13, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
          .padding(.horizontal, 12).padding(.vertical, 6)
          .background(BoldTheme.Colors.glassStrong)
          .overlay(Capsule().strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
          .clipShape(Capsule())
        }
      }
    }
  }

  /// Full-width segmented control: CFB | PRO BALL | PICKEMS.
  private var sectionToggle: some View {
    HStack(spacing: 4) {
      ForEach([(MyPicksSection.cfb, "CFB"), (.nfl, "PRO BALL"), (.pickems, "PICKEMS")], id: \.0) { value, label in
        let active = section == value
        Button {
          withAnimation(.easeInOut(duration: 0.2)) { sectionBinding.wrappedValue = value }
        } label: {
          Text(label)
            .font(BoldTheme.Fonts.body(13, weight: .bold))
            .tracking(0.4)
            .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
              RoundedRectangle(cornerRadius: 11)
                .fill(active ? (value == .pickems ? BoldTheme.Colors.pickemsAccent.opacity(0.18) : BoldTheme.Colors.gold) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func errorState(_ message: String) -> some View {
    VStack(spacing: 8) {
      Text("Couldn't load your picks").font(BoldTheme.Fonts.display(22)).foregroundColor(BoldTheme.Colors.text)
      Text(message).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
      Button("Retry") { Task { await viewModel.load() } }
        .font(BoldTheme.Fonts.body(14, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.goldDeep)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 40)
  }

  // MARK: Underdog section

  @ViewBuilder private var underdogSection: some View {
    if let ctx = context, season == ctx.season {
      underdogThisWeek(ctx: ctx)
    }
    underdogStats
    sectionLabel("HISTORY")
    if historyEntries.isEmpty {
      emptyHistory("No past \(section == .nfl ? "Pro Ball" : "CFB") picks \(season.map { "in \($0)" } ?? "yet").")
    } else {
      VStack(spacing: 0) {
        ForEach(Array(historyEntries.enumerated()), id: \.element.id) { i, entry in
          underdogHistoryRow(entry)
          if i < historyEntries.count - 1 {
            Rectangle().fill(BoldTheme.Colors.border).frame(height: 1).padding(.leading, 62)
          }
        }
      }
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 18))
      .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }
  }

  private func underdogThisWeek(ctx: CurrentContext) -> some View {
    let entry = thisWeekEntry
    let status = underdogStatus(entry)
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(verbatim: "\(section == .nfl ? "PRO BALL" : "CFB") · WEEK \(formatWeekLabel(ctx.week))")
          .font(BoldTheme.Fonts.mono(11, weight: .semibold))
          .tracking(0.8)
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer()
        statusChip(status)
      }

      if let entry {
        HStack(spacing: 14) {
          teamLogo(entry.pick.picked_team_id, size: 52)
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(entry.pickedName)
                .font(BoldTheme.Fonts.body(20, weight: .bold))
                .foregroundColor(BoldTheme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              if let sp = entry.spread {
                Text(verbatim: "+\(formatNumber(sp))")
                  .font(BoldTheme.Fonts.mono(16, weight: .semibold))
                  .foregroundColor(BoldTheme.Colors.goldDeep)
              }
            }
            Text(verbatim: "vs \(entry.opponentName) · \(entry.scoreLine ?? kickoffText(entry.game.startTime))")
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(BoldTheme.Colors.textDim)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
        }
      } else {
        Text(status == .missed ? "Every game has kicked off. Catch the next one." : "Pick one underdog. If they win outright, you bank the spread.")
          .font(BoldTheme.Fonts.body(14))
          .foregroundColor(BoldTheme.Colors.textDim)
      }

      if status != .missed {
        Button { appState.goToUnderdog(sport: sport) } label: {
          Text(entry == nil ? "Pick now →" : (status == .picked ? "Change pick →" : "View games →"))
            .font(BoldTheme.Fonts.body(14, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(entry == nil || status == .picked ? BoldTheme.Colors.gold : BoldTheme.Colors.track)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(18)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
  }

  private var underdogStats: some View {
    let decided = sportEntries.filter { $0.outcome != .pending }
    let wins = decided.filter { $0.outcome == .win }.count
    let losses = decided.count - wins
    let points = sportEntries.reduce(0) { $0 + $1.points }
    let rate = decided.isEmpty ? "–" : "\(Int((Double(wins) / Double(decided.count) * 100).rounded()))%"
    return HStack(spacing: 10) {
      statTile("RECORD", "\(wins)–\(losses)")
      statTile("POINTS", points > 0 ? "+\(formatNumber(points))" : "0", highlight: points > 0)
      statTile("HIT RATE", rate)
    }
  }

  private func underdogHistoryRow(_ entry: UnderdogWeekEntry) -> some View {
    HStack(spacing: 12) {
      VStack(spacing: 0) {
        Text("WK").font(BoldTheme.Fonts.mono(9, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
        Text(verbatim: formatWeekLabel(entry.pick.week))
          .font(BoldTheme.Fonts.mono(15, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
      }
      .frame(width: 34)

      teamLogo(entry.pick.picked_team_id, size: 30)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(entry.pickedName)
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
            .lineLimit(1)
          if let sp = entry.spread {
            Text(verbatim: "+\(formatNumber(sp))")
              .font(BoldTheme.Fonts.mono(12))
              .foregroundColor(BoldTheme.Colors.textDim)
          }
        }
        Text(verbatim: "vs \(entry.opponentName)")
          .font(BoldTheme.Fonts.body(12))
          .foregroundColor(BoldTheme.Colors.textFaint)
          .lineLimit(1)
      }

      Spacer(minLength: 6)
      VStack(alignment: .trailing, spacing: 3) {
        resultBadge(entry)
        if let score = entry.scoreLine {
          Text(score)
            .font(BoldTheme.Fonts.mono(11))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  @ViewBuilder private func resultBadge(_ entry: UnderdogWeekEntry) -> some View {
    switch entry.outcome {
    case .win:
      Text(verbatim: "+\(formatNumber(entry.points))")
        .font(BoldTheme.Fonts.mono(13, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.text)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(BoldTheme.Colors.gold)
        .clipShape(Capsule())
    case .loss:
      Text("MISS")
        .font(BoldTheme.Fonts.mono(11, weight: .semibold))
        .tracking(0.5)
        .foregroundColor(BoldTheme.Colors.textDim)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(BoldTheme.Colors.track)
        .clipShape(Capsule())
    case .pending:
      Text(entry.isLive ? "LIVE" : "PENDING")
        .font(BoldTheme.Fonts.mono(11, weight: .semibold))
        .tracking(0.5)
        .foregroundColor(entry.isLive ? Color(hex: 0xC6402A) : BoldTheme.Colors.textFaint)
    }
  }

  // MARK: Pickems section

  @ViewBuilder private var pickemsSection: some View {
    if let ctx = viewModel.nflContext, season == ctx.season {
      pickemsThisWeek(ctx: ctx)
    }
    pickemsStats
    sectionLabel("HISTORY")
    if pickemsHistory.isEmpty {
      emptyHistory("No past Pickems weeks \(season.map { "in \($0)" } ?? "yet").")
    } else {
      VStack(spacing: 0) {
        ForEach(Array(pickemsHistory.enumerated()), id: \.element.id) { i, week in
          pickemsHistoryRow(week)
          if i < pickemsHistory.count - 1 {
            Rectangle().fill(BoldTheme.Colors.border).frame(height: 1).padding(.leading, 60)
          }
        }
      }
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 18))
      .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }
  }

  private func pickemsThisWeek(ctx: CurrentContext) -> some View {
    let total = viewModel.pickemsThisWeekTotal
    let picked = viewModel.pickemsThisWeekPicked
    let correct = viewModel.pickemsThisWeekCorrect
    let wrong = viewModel.pickemsThisWeekWrong
    let open = viewModel.pickemsThisWeekOpen
    let status: PickStatus = total == 0 ? .none : (picked >= total ? .picked : (open > 0 ? .pickNow : (picked == 0 ? .missed : .partial(picked, total))))
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(verbatim: "PICKEMS · WEEK \(formatWeekLabel(ctx.week))")
          .font(BoldTheme.Fonts.mono(11, weight: .semibold))
          .tracking(0.8)
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer()
        statusChip(status)
      }

      if total == 0 {
        Text("No games on the board yet.")
          .font(BoldTheme.Fonts.body(14))
          .foregroundColor(BoldTheme.Colors.textDim)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(verbatim: "\(picked)")
            .font(BoldTheme.Fonts.display(40))
            .foregroundColor(BoldTheme.Colors.text)
          Text(verbatim: "of \(total) picked")
            .font(BoldTheme.Fonts.body(15, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        progressBar(value: picked, total: total, color: BoldTheme.Colors.pickemsAccent)
        if picked > 0 {
          HStack(spacing: 14) {
            legendDot(BoldTheme.Colors.green, "\(correct) correct")
            legendDot(Color(hex: 0xC6402A), "\(wrong) wrong")
            legendDot(BoldTheme.Colors.textFaint, "\(viewModel.pickemsThisWeekUnfinished) to play")
          }
        } else if open > 0 {
          Text(verbatim: "\(open) game\(open == 1 ? "" : "s") still open")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
      }

      if open > 0 {
        Button { appState.goToPickems() } label: {
          Text(picked == 0 ? "Pick now →" : (picked < total ? "Finish your picks →" : "Change picks →"))
            .font(BoldTheme.Fonts.body(14, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(BoldTheme.Colors.pickemsAccentDeep)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(18)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
  }

  private var pickemsStats: some View {
    let weeks = viewModel.pickemsWeeks.filter { $0.season == season }
    let correct = weeks.reduce(0) { $0 + $1.correct }
    let decided = weeks.reduce(0) { $0 + $1.decided }
    let acc = decided == 0 ? "–" : "\(Int((Double(correct) / Double(decided) * 100).rounded()))%"
    return HStack(spacing: 10) {
      statTile("CORRECT", "\(correct)", highlight: correct > 0, pickems: true)
      statTile("ACCURACY", acc)
      statTile("WEEKS", "\(weeks.count)")
    }
  }

  private func pickemsHistoryRow(_ week: PickemsWeekEntry) -> some View {
    HStack(spacing: 12) {
      VStack(spacing: 0) {
        Text("WK").font(BoldTheme.Fonts.mono(9, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
        Text(verbatim: formatWeekLabel(week.week))
          .font(BoldTheme.Fonts.mono(15, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
      }
      .frame(width: 34)

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(verbatim: "\(week.correct) of \(week.decided) correct")
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
          Spacer()
          if week.decided > 0 {
            Text(verbatim: "\(Int((Double(week.correct) / Double(week.decided) * 100).rounded()))%")
              .font(BoldTheme.Fonts.mono(13, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.pickemsAccent)
          }
        }
        progressBar(value: week.correct, total: max(week.decided, 1), color: BoldTheme.Colors.green)
        if week.picked > week.decided {
          Text(verbatim: "\(week.picked - week.decided) still to play")
            .font(BoldTheme.Fonts.body(11))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  // MARK: Shared pieces

  enum PickStatus: Equatable { case none, pickNow, picked, live, won, lost, missed, partial(Int, Int) }

  private func underdogStatus(_ entry: UnderdogWeekEntry?) -> PickStatus {
    guard let entry else { return viewModel.underdogOpen[sport] == true ? .pickNow : .missed }
    if entry.isLive { return .live }
    switch entry.outcome {
    case .win: return .won
    case .loss: return .lost
    case .pending: return .picked
    }
  }

  @ViewBuilder private func statusChip(_ status: PickStatus) -> some View {
    let (text, fg, bg): (String, Color, Color) = {
      switch status {
      case .none: return ("", .clear, .clear)
      case .pickNow: return ("No pick yet", BoldTheme.Colors.text, BoldTheme.Colors.gold)
      case .picked: return ("Picked ✓", BoldTheme.Colors.green, BoldTheme.Colors.green.opacity(0.13))
      case .live: return ("Live", Color(hex: 0xC6402A), Color(hex: 0xC6402A).opacity(0.12))
      case .won: return ("Won", BoldTheme.Colors.text, BoldTheme.Colors.gold)
      case .lost: return ("Lost", BoldTheme.Colors.textDim, BoldTheme.Colors.track)
      case .missed: return ("Missed", BoldTheme.Colors.textDim, BoldTheme.Colors.track)
      case let .partial(p, t): return ("\(p) of \(t)", BoldTheme.Colors.textDim, BoldTheme.Colors.track)
      }
    }()
    if status != .none {
      Text(text)
        .font(BoldTheme.Fonts.body(12, weight: .bold))
        .foregroundColor(fg)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(bg)
        .clipShape(Capsule())
    }
  }

  private func statTile(_ label: String, _ value: String, highlight: Bool = false, pickems: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(BoldTheme.Fonts.mono(10, weight: .semibold))
        .tracking(0.8)
        .foregroundColor(BoldTheme.Colors.textFaint)
      Text(value)
        .font(BoldTheme.Fonts.display(24))
        .foregroundColor(highlight ? (pickems ? BoldTheme.Colors.pickemsAccent : BoldTheme.Colors.goldDeep) : BoldTheme.Colors.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(BoldTheme.Fonts.mono(11, weight: .semibold))
      .tracking(0.9)
      .foregroundColor(BoldTheme.Colors.textFaint)
      .padding(.top, 4)
      .padding(.bottom, -8)
  }

  private func emptyHistory(_ text: String) -> some View {
    Text(text)
      .font(BoldTheme.Fonts.body(13))
      .foregroundColor(BoldTheme.Colors.textDim)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 24)
      .background(BoldTheme.Colors.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func progressBar(value: Int, total: Int, color: Color) -> some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(BoldTheme.Colors.track)
        Capsule().fill(color)
          .frame(width: total > 0 ? geo.size.width * CGFloat(min(value, total)) / CGFloat(total) : 0)
      }
    }
    .frame(height: 6)
  }

  private func legendDot(_ color: Color, _ text: String) -> some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(text).font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
    }
  }

  private func teamLogo(_ teamId: UUID, size: CGFloat) -> some View {
    AsyncImage(url: viewModel.logoMap[teamId]) { phase in
      switch phase {
      case .success(let img): img.resizable().scaledToFit()
      default: Image(systemName: "football").resizable().scaledToFit().padding(size * 0.18).foregroundColor(BoldTheme.Colors.textFaint)
      }
    }
    .frame(width: size, height: size)
  }

  private func kickoffText(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "EEE h:mm a"
    return f.string(from: date)
  }

  private func formatNumber(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
  }
}
