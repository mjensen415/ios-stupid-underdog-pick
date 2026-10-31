import SwiftUI
import Supabase

@MainActor
final class GamesViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published var games: [Game] = []
  @Published var availableWeeks: [Int] = []
  @Published var selectedWeek: Int = 1
  /// The live week for this sport (selectedWeek's starting value). Weeks
  /// before it get a compact "your pick" note instead of the big banner.
  @Published var currentWeek: Int = 1
  @Published var season: Int = 2025
  @Published var selectedGameId: UUID? = nil
  /// The saved pick row, for its picked team and Pro Ball locked line.
  /// Nil right after a fresh pick -- the banner then falls back to the
  /// game's current underdog/line, which is exactly what just got locked.
  @Published var myPick: Pick? = nil
  @Published var savingPick = false
  @Published var toastMessage: String?
  @Published var sport: String = "cfb"
  /// Set to a fresh id only on a just-now successful pick (never on load),
  /// so GamesView can fire a one-shot confetti burst without re-celebrating
  /// every time the screen re-renders an existing pick.
  @Published var pickCelebrationTrigger: UUID?

  // Per-group Underdog picks: nil = "my shared pick" (unchanged
  // default, every existing call site keeps writing this). A real
  // group id means the pick screen writes/reads that group's own
  // scoped pick, falling back to the shared pick until customized.
  @Published var myGroups: [MyGroup] = []
  @Published var activeGroupId: UUID?
  @Published var copyingPicks = false

  /// Where to watch (SUP Pro): ESPN event id per game, and networks per
  /// event id from game_broadcasts. Only loaded while watch_links is on.
  @Published var espnIds: [UUID: String] = [:]
  @Published var broadcasts: [String: [BroadcastNetwork]] = [:]
  var watchEnabled = false

  var underdogGroups: [MyGroup] {
    myGroups.filter { $0.game_type != .pickems && ($0.sport.rawValue == sport || $0.sport == .both) }
  }

  private let client: SupabaseClient
  private var logoMap: [UUID: URL] = [:]
  private var toastDismissTask: Task<Void, Never>?

  init(client: SupabaseClient) { self.client = client }

  func logoURL(for id: UUID?) -> URL? {
    guard let id, let s = logoMap[id] else { return nil }
    return s
  }

  private func flashToast(_ message: String) {
    toastDismissTask?.cancel()
    toastMessage = message
    toastDismissTask = Task {
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      guard !Task.isCancelled else { return }
      toastMessage = nil
    }
  }

  /// Team logos, shared across sports and screen reloads: 874 rows that
  /// rarely change, so one fetch per app launch is enough.
  private static var logoMapCache: [UUID: URL]?

  private static func fetchLogoMap(client: SupabaseClient) async throws -> [UUID: URL] {
    if let hit = logoMapCache { return hit }
    // Inline team logo fetch to avoid TeamService dependency
    struct T: Decodable { let id: UUID; let logo_url: String? }
    let teamRes = try await client
      .from("teams")
      .select("id, logo_url")
      .execute()
    let teams = try JSONDecoder().decode([T].self, from: teamRes.data)
    let map = Dictionary(uniqueKeysWithValues: teams.map { t in (t.id, t.logo_url.flatMap { URL(string: $0) }) }).compactMapValues { $0 }
    logoMapCache = map
    return map
  }

  /// Everything after the season/week lookup runs at the same time instead
  /// of one request after another: the list shows as soon as games and
  /// logos are in, then the pick and watch links fill in.
  func loadInitial() async {
    isLoading = true; errorText = nil
    defer { isLoading = false }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: sport)
      season = ctx.season
      selectedWeek = ctx.week
      currentWeek = ctx.week
      let client = client, season = season, week = selectedWeek, sport = sport
      async let weeks = GamesService(client: client).distinctWeeks(forSeason: season, sport: sport)
      async let fetched = GamesService(client: client).fetch(season: season, week: week, sport: sport)
      async let logos = Self.fetchLogoMap(client: client)
      async let groups = (try? await GroupsService(client: client).fetchMyGroups()) ?? []

      // Logos before games: logoMap isn't published, so rows must find it
      // filled on their first render.
      logoMap = try await logos
      games = try await fetched
      isLoading = false
      availableWeeks = try await weeks
      myGroups = await groups
      if let activeGroupId, !underdogGroups.contains(where: { $0.group_id == activeGroupId }) {
        self.activeGroupId = nil
      }
      async let watch: Void = loadWatch()
      try await loadExistingPick()
      await watch
    } catch {
      errorText = error.localizedDescription
    }
  }

  /// Switch sport and reload the whole screen for it (season/week can
  /// differ between sports, so this re-runs the full loadInitial flow
  /// rather than just re-filtering the existing games list).
  func switchSport(to newSport: String) async {
    guard newSport != sport else { return }
    sport = newSport
    await loadInitial()
  }

  func loadGames() async throws {
    isLoading = true; defer { isLoading = false }
    errorText = nil
    let svc = GamesService(client: client)
    games = try await svc.fetch(season: season, week: selectedWeek, sport: sport)
    isLoading = false
    await loadWatch()
  }

  /// Networks for this week's games. Public data, read-only; failures just
  /// leave the capsules off.
  func loadWatch() async {
    guard watchEnabled, !games.isEmpty else { espnIds = [:]; broadcasts = [:]; return }
    let data = ProDataService(client: client)
    let ids = await data.espnIds(gameIds: games.map(\.id), sport: sport)
    espnIds = ids
    broadcasts = await data.broadcasts(eventIds: Array(ids.values))
  }

  /// The links for one game, national first (empty when none).
  func watchLinks(for g: Game) -> [WatchLink] {
    guard let eid = espnIds[g.id], let nets = broadcasts[eid], !nets.isEmpty else { return [] }
    return WatchLinks.links(sport: sport == "nfl" ? .nfl : .cfb, eventId: eid, networks: nets)
  }

  func loadExistingPick() async throws {
    if let pick = try await PicksService(client: client).myPick(season: season, week: selectedWeek, sport: sport, groupId: activeGroupId) {
      selectedGameId = pick.game_id
      myPick = pick
    } else {
      selectedGameId = nil
      myPick = nil
    }
  }

  func resetToSharedPick() async {
    guard let activeGroupId else { return }
    do {
      try await PicksService(client: client).resetGroupPick(groupId: activeGroupId, season: season, week: selectedWeek, sport: sport)
      try await loadExistingPick()
      flashToast("Reset to shared pick")
    } catch {
      flashToast("Couldn’t reset: \(friendlyPickErrorMessage(error))")
    }
  }

  func copyPick(from sourceGroupId: UUID?) async {
    guard let activeGroupId else { return }
    copyingPicks = true
    defer { copyingPicks = false }
    do {
      let result = try await PicksService(client: client).copyGroupPick(targetGroupId: activeGroupId, sourceGroupId: sourceGroupId, season: season, week: selectedWeek, sport: sport)
      try await loadExistingPick()
      if !result.copied {
        flashToast(result.reason == "GAME_LOCKED" ? "That pick's game already started." : "Nothing to copy yet.")
      } else {
        flashToast("Pick copied")
      }
    } catch {
      flashToast("Couldn’t copy: \(friendlyPickErrorMessage(error))")
    }
  }

  /// NFL lines are effectively guaranteed to post (just not synced yet at
  /// any given moment) -- NFL keeps showing every game, with GameRowView's
  /// muted "LINE TBD" treatment covering that brief gap. CFB is different:
  /// most of a week's slate is small-school matchups (Div II, Div III,
  /// NAIA) that never get a market line at all, at any point -- confirmed
  /// against real Week 1 data, 358 of 456 CFB games never had a spread,
  /// 116 of those were already final with still no line ever posted.
  /// Zero-line CFB games are hidden entirely now (pre- or post-kickoff) --
  /// matches web's IndexBold.tsx, which found the old "still show it
  /// pre-kickoff, a line might post" exception was itself leaking
  /// unpickable "--" rows into the list before kickoff too.
  var visibleGames: [Game] {
    guard sport == "cfb" else { return games }
    return games.filter { g in g.derivedFavoriteTeamId != nil }
  }

  /// Your current pick's game has kicked off (or locked) -- the pick is
  /// final for the week, so no other game can be picked either. The server
  /// enforces this too (upsert_weekly_pick); this just stops the app from
  /// offering a switch that can only fail.
  var currentPickIsLocked: Bool {
    guard let id = selectedGameId, let g = games.first(where: { $0.id == id }) else { return false }
    return g.picksLocked == true || g.startTime <= Date() || (g.status != nil && g.status != "scheduled")
  }

  func canPick(_ g: Game) -> Bool {
    if currentPickIsLocked && g.id != selectedGameId { return false }
    if g.picksLocked == true {
      #if DEBUG
      print("[canPick] BLOCKED (picksLocked) \(g.awayTeam ?? "?") @ \(g.homeTeam ?? "?")")
      #endif
      return false
    }
    if g.startTime < Date() {
      #if DEBUG
      print("[canPick] BLOCKED (startTime \(g.startTime) < now \(Date())) \(g.awayTeam ?? "?") @ \(g.homeTeam ?? "?")")
      #endif
      return false
    }
    let fav = g.derivedFavoriteTeamId
    #if DEBUG
    if fav == nil {
      let spreadText: String = g.latestSpread == nil ? "nil" : "\(g.latestSpread!)"
      let homeText: String = g.homeTeamId?.uuidString ?? "nil"
      let awayText: String = g.awayTeamId?.uuidString ?? "nil"
      print("[canPick] BLOCKED (no favorite) \(g.awayTeam ?? "?") @ \(g.homeTeam ?? "?") spread=\(spreadText) home=\(homeText) away=\(awayText)")
    } else {
      print("[canPick] OK \(g.awayTeam ?? "?") @ \(g.homeTeam ?? "?")")
    }
    #endif
    return fav != nil
  }

  // The swipe button previously always read "Pick this upset," even fully
  // greyed out and disabled on a game nobody could act on anymore -- no
  // indication of *why*. Order matters: check live/final before picksLocked,
  // since a live or finished game is also picksLocked, and "Game Live"/
  // "Game Over" is the more useful answer than the generic "Locked."
  func swipeActionLabel(for g: Game) -> String {
    if canPick(g) {
      // Mirrors web's PICK -> CHANGE relabel: your existing pick only
      // locks at its own kickoff, so any other still-open game stays a
      // real option (and a real swipe action) until then -- just says
      // what swiping actually does now.
      let dogIsHome = g.derivedUnderdogTeamId != nil && g.derivedUnderdogTeamId == g.homeTeamId
      let dog = (dogIsHome ? g.homeDisplay : g.awayDisplay) ?? "the dog"
      let line = g.underdogSpread.map { " +\(jsNumber($0))" } ?? ""
      return (selectedGameId != nil && selectedGameId != g.id ? "Change to " : "Pick ") + dog + line
    }
    if currentPickIsLocked && g.id != selectedGameId { return "Your pick is locked" }
    if g.status == "in_progress" { return "Game live" }
    if g.status == "final" { return "Game over" }
    return "Locked"
  }

  /// `haptic` is off for the pick card, which plays its own
  /// .sensoryFeedback on lock-in. Returns whether the pick saved.
  @discardableResult
  func pickUnderdog(for g: Game, haptic: Bool = true) async -> Bool {
    #if DEBUG
    print("[pickUnderdog] BUTTON FIRED for \(g.awayTeam ?? "?") @ \(g.homeTeam ?? "?"), canPick=\(canPick(g))")
    #endif
    guard canPick(g) else { return false }
    guard let pickedId = g.derivedUnderdogTeamId else {
      #if DEBUG
      print("[pickUnderdog] BLOCKED: derivedUnderdogTeamId is nil")
      #endif
      return false
    }
    let previous = selectedGameId
    let previousPick = myPick
    selectedGameId = g.id
    myPick = nil
    savingPick = true; defer { savingPick = false }
    do {
      _ = try await PicksService(client: client)
        .upsertPick(gameId: g.id, pickedTeamId: pickedId, season: season, week: selectedWeek, groupId: activeGroupId)
      flashToast("Picked \(g.awayDisplay ?? "") @ \(g.homeDisplay ?? "")")
      if haptic { Haptics.success() }
      pickCelebrationTrigger = UUID()
      // They just used the swipe gesture successfully -- the hint banner
      // has nothing left to teach them. Written directly to UserDefaults
      // (shared key with GamesView's @AppStorage) since the ViewModel has
      // no view-level binding to flip.
      UserDefaults.standard.set(true, forKey: GamesView.swipeHintDefaultsKey)
      #if DEBUG
      print("[pickUnderdog] SUCCESS, toast=\(toastMessage ?? "")")
      #endif
      return true
    } catch {
      selectedGameId = previous
      myPick = previousPick
      flashToast("Couldn’t save pick: \(friendlyPickErrorMessage(error))")
      #if DEBUG
      print("[pickUnderdog] SAVE FAILED: \(error)")
      #endif
      return false
    }
  }

  /// Lock-in re-check for the pick card. Also refreshes this game's row,
  /// so the list and the post-pick banner show the line that was locked.
  func recheckLine(for g: Game) async -> LineCheck {
    let current = await LineRecheck.currentHomeSpread(gameId: g.id, client: client)
    let check = LineRecheck.evaluate(shownHomeSpread: g.latestSpread, currentHomeSpread: current)
    if check != .unchanged, let current, let i = games.firstIndex(where: { $0.id == g.id }) {
      games[i] = games[i].withLatestSpread(current)
    }
    return check
  }

  func clearPickForWeek() async {
    let previous = selectedGameId
    let previousPick = myPick
    selectedGameId = nil
    myPick = nil
    savingPick = true; defer { savingPick = false }
    do {
      try await PicksService(client: client).clearPick(season: season, week: selectedWeek, sport: sport, groupId: activeGroupId)
      flashToast("Pick cleared")
    } catch {
      selectedGameId = previous
      myPick = previousPick
      flashToast("Couldn’t clear: \(friendlyPickErrorMessage(error))")
    }
  }
}

// Explicit light text for content sitting on a solid GREEN chip/banner --
// GREEN stays dark/saturated under Frost even though the page went light,
// so BoldTheme.Colors.text (now dark Ink) can't be reused there. Mirrors
// web's TEXT_ON_GREEN constant in src/pages/IndexBold.tsx.
private let textOnGreen = Color(hex: 0xF2EFE3)

struct GamesView: View {
  @StateObject var viewModel: GamesViewModel
  @EnvironmentObject var appState: AppState
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  @EnvironmentObject private var pro: ProStore

  private var isPro: Bool { pro.isPro(admin: featureFlags.isAdmin) }
  private var watchEnabled: Bool { featureFlags.isVisible(FeatureFlagKey.watchLinks) }
  @State private var shareImage: Image?
  @State private var searchQuery: String = ""
  @State private var showGroupPicker = false
  @State private var showCopyPicksSheet = false

  private var activeGroupName: String? {
    guard let id = viewModel.activeGroupId else { return nil }
    return viewModel.underdogGroups.first { $0.group_id == id }?.name ?? "this group"
  }

  // Picking here is a swipe-left gesture on the row (see .swipeActions
  // below) with no other on-screen affordance -- feedback showed people
  // land on this screen and don't discover it. One-time dismissible
  // banner, shown until dismissed or until they successfully make a pick
  // (whichever first -- see GamesViewModel.pickUnderdog).
  static let swipeHintDefaultsKey = "hasSeenSwipeToPickHint"
  @State private var tappedGame: Game?

  // The picked team's row already tints gold + gets a checkmark badge
  // (GameRowView.isSelected) -- this banner is the "which game, at a
  // glance, without scrolling to find the tinted row" signal on top.
  private var pickedGame: Game? {
    guard let id = viewModel.selectedGameId else { return nil }
    return viewModel.games.first { $0.id == id }
  }

  /// "Your pick" bar, pinned under the filter bar (round 2): which game,
  /// at a glance, without scrolling to find the green row. Tap opens its
  /// pick card. Only for the live week; past weeks get pastWeekNote.
  @ViewBuilder
  private var pinnedPickBar: some View {
    if let g = pickedGame, viewModel.selectedWeek >= viewModel.currentWeek {
      // The team actually picked (a Pro Ball line can move after the pick,
      // even flipping who the underdog is), scored on its locked line.
      let savedPick = viewModel.myPick?.game_id == g.id ? viewModel.myPick : nil
      let pickedTeamId = savedPick?.picked_team_id ?? g.derivedUnderdogTeamId
      let pickedIsHome = pickedTeamId != nil && pickedTeamId == g.homeTeamId
      let dogName = (pickedIsHome ? g.homeDisplay : g.awayDisplay) ?? "Your pick"
      let favoriteName = (pickedIsHome ? g.awayDisplay : g.homeDisplay) ?? ""
      let points: Double? = savedPick.map { $0.winPoints(on: g) } ?? g.underdogSpread
      HStack(spacing: 10) {
        RetryingAsyncImage(url: viewModel.logoURL(for: pickedTeamId)) { img in
          img.resizable().scaledToFit()
        } placeholder: {
          Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(textOnGreen)
        }
        .frame(width: 26, height: 26)
        (Text("Your pick: ").foregroundColor(textOnGreen.opacity(0.75))
          + Text(verbatim: dogName + (points.map { " +\(jsNumber($0))" } ?? "")).bold()
          + Text(verbatim: " · " + pickStatus(g, pickedTeamId: pickedTeamId, points: points)).foregroundColor(textOnGreen.opacity(0.85)))
          .font(BoldTheme.Fonts.body(14))
          .foregroundColor(textOnGreen)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 4)
        if let shareImage, let sp = points {
          // No singular `item: Image` initializer exists on ShareLink.
          ShareLink(
            items: [shareImage],
            preview: { img in SharePreview(Text(verbatim: "\(dogName) +\(jsNumber(sp))"), image: img) }
          ) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(textOnGreen)
              .frame(width: 30, height: 30)
          }
          .accessibilityLabel("Share your pick")
        }
      }
      .padding(.horizontal, BoldTheme.Space.s3)
      .frame(minHeight: 44)
      .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.green))
      .contentShape(Rectangle())
      .onTapGesture { tappedGame = g }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isButton)
      .task(id: "\(g.id)-\(points ?? 0)") {
        guard let sp = points else { shareImage = nil; return }
        if let uiImage = renderShareCardImage(dogName: dogName, spread: sp, favoriteName: favoriteName) {
          shareImage = Image(uiImage: uiImage)
        }
      }
    }
  }

  /// "Fri 4:30 PM", "Live 14–7", "won, +3 pts", "lost".
  private func pickStatus(_ g: Game, pickedTeamId: UUID?, points: Double?) -> String {
    let pickedHome = pickedTeamId == g.homeTeamId
    if g.status == "final", let pickedTeamId {
      return g.outcome(forPickedTeamId: pickedTeamId) == .win
        ? "won" + (points.map { ", +\(jsNumber($0)) pts" } ?? "")
        : "lost"
    }
    if g.status == "in_progress" {
      if let h = g.homePoints, let a = g.awayPoints {
        return "Live \(pickedHome ? h : a)–\(pickedHome ? a : h)"
      }
      return "Live"
    }
    let f = DateFormatter()
    f.dateFormat = "EEE h:mm a"
    return f.string(from: g.startTime)
  }

  /// Looking back at an earlier week: a one-line reminder of what you
  /// picked and how it went (or that you sat it out), not the full banner.
  @ViewBuilder
  private var pastWeekNote: some View {
    let week = formatWeekLabel(viewModel.selectedWeek)
    if let g = pickedGame {
      let savedPick = viewModel.myPick?.game_id == g.id ? viewModel.myPick : nil
      let pickedTeamId = savedPick?.picked_team_id ?? g.derivedUnderdogTeamId
      let pickedIsHome = pickedTeamId != nil && pickedTeamId == g.homeTeamId
      let name = (pickedIsHome ? g.homeDisplay : g.awayDisplay) ?? "Your pick"
      let spread: Double? = savedPick.map { $0.winPoints(on: g) } ?? g.underdogSpread
      let outcome = pickedTeamId.map { g.outcome(forPickedTeamId: $0) } ?? .pending
      HStack(spacing: 10) {
        RetryingAsyncImage(url: viewModel.logoURL(for: pickedTeamId)) { img in
          img.resizable().scaledToFit()
        } placeholder: {
          Image(systemName: "football").resizable().scaledToFit().foregroundColor(BoldTheme.Colors.textFaint)
        }
        .frame(width: 22, height: 22)
        Text(verbatim: "Week \(week) pick:")
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
        + Text(verbatim: " \(name)")
          .font(BoldTheme.Fonts.body(13, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
        + Text(verbatim: spread.map { " +\(jsNumber($0))" } ?? "")
          .font(BoldTheme.Fonts.body(13, weight: .bold))
          .foregroundColor(BoldTheme.Role.line)
        Spacer(minLength: 6)
        switch outcome {
        case .win: SupPill(text: spread.map { "Won +\(jsNumber($0))" } ?? "Won", kind: .green)
        case .loss: SupPill(text: "Missed", kind: .gray)
        case .pending: SupPill(text: g.status == "in_progress" ? "Live" : "Pending", kind: .gray)
        }
      }
      .lineLimit(1)
      .padding(.horizontal, 14).padding(.vertical, 12)
      .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
      .padding(.horizontal, BoldTheme.Space.margin)
      .padding(.bottom, BoldTheme.Space.cardGap)
    } else if !viewModel.games.isEmpty && viewModel.selectedGameId == nil {
      HStack(spacing: 8) {
        Image(systemName: "minus.circle")
          .foregroundColor(BoldTheme.Colors.textFaint)
        Text(verbatim: "No pick in Week \(week).")
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer()
      }
      .padding(.horizontal, 14).padding(.vertical, 12)
      .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
      .padding(.horizontal, BoldTheme.Space.margin)
      .padding(.bottom, BoldTheme.Space.cardGap)
    }
  }

  /// One-line note above the slate (de-slop #12): rows have no PICK
  /// button, so say how to pick. Scrolls away with the games.
  private var selectHint: some View {
    HStack(spacing: BoldTheme.Space.s2) {
      Image(systemName: "arrow.left")
        .font(.system(size: 14, weight: .semibold))
      Text("Slide or tap to select")
        .font(BoldTheme.Fonts.body(14))
    }
    .foregroundColor(BoldTheme.Colors.textDim)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, BoldTheme.Space.margin)
    .padding(.top, 14)
    .padding(.bottom, BoldTheme.Space.s3)
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundColor(BoldTheme.Colors.textFaint)
        .font(.system(size: 14, weight: .medium))
      TextField("Search teams", text: $searchQuery)
        .focused($searchFocused)
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.text)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.words)
      if !searchQuery.isEmpty {
        Button {
          searchQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(Capsule().fill(BoldTheme.Colors.card))
  }

  // Matches either team's full or short name -- a search for "OSU" alone
  // wouldn't hit anything useful given how inconsistently team short names
  // are populated, so this sticks to substring matching on the names
  // actually shown on the row.
  private var filteredGames: [Game] {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return viewModel.visibleGames }
    return viewModel.visibleGames.filter { g in
      [g.homeTeam, g.awayTeam, g.homeShort, g.awayShort].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }

  @ViewBuilder private var groupPicker: some View {
    if viewModel.underdogGroups.count > 1 {
      Button {
        showGroupPicker = true
      } label: {
        HStack(spacing: 6) {
          Text("Picking for")
            .font(BoldTheme.Fonts.body(11, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textFaint)
          Text(activeGroupName ?? "My shared pick")
            .font(BoldTheme.Fonts.body(12.5, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
          Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(BoldTheme.Colors.card)
        .overlay(Capsule().strokeBorder(viewModel.activeGroupId != nil ? BoldTheme.Colors.text : .clear, lineWidth: 1.5))
        .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, BoldTheme.Space.margin)
      .padding(.bottom, BoldTheme.Space.s3)
      .confirmationDialog("Picking for", isPresented: $showGroupPicker, titleVisibility: .visible) {
        Button("My shared pick") { viewModel.activeGroupId = nil }
        ForEach(viewModel.underdogGroups) { g in
          Button(g.name) { viewModel.activeGroupId = g.group_id }
        }
        Button("Cancel", role: .cancel) {}
      }
    }
  }

  @ViewBuilder private var groupModeBanner: some View {
    if let name = activeGroupName {
      HStack(alignment: .center, spacing: 10) {
        Text("Picking for **\(name)** only \u{2014} your other groups keep your shared pick.")
          .font(BoldTheme.Fonts.body(11.5))
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 4) {
          Button("Copy pick from\u{2026}") { showCopyPicksSheet = true }
            .font(BoldTheme.Fonts.body(11.5, weight: .bold))
            .foregroundColor(BoldTheme.Colors.green)
          Button("Reset to shared") { Task { await viewModel.resetToSharedPick() } }
            .font(BoldTheme.Fonts.body(11, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      .padding(BoldTheme.Space.s3)
      .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
      .padding(.horizontal, BoldTheme.Space.margin)
      .padding(.bottom, BoldTheme.Space.cardGap)
      .sheet(isPresented: $showCopyPicksSheet) {
        copyPicksSheet
      }
    }
  }

  private var copyPicksSheet: some View {
    NavigationStack {
      List {
        Section {
          Text("Copy this week's pick into **\(activeGroupName ?? "this group")**. If the game's already started, it can't be copied.")
            .font(BoldTheme.Fonts.body(12.5))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        Section {
          Button("My shared pick") {
            Task {
              await viewModel.copyPick(from: nil)
              showCopyPicksSheet = false
            }
          }
          .disabled(viewModel.copyingPicks)
          ForEach(viewModel.underdogGroups.filter { $0.group_id != viewModel.activeGroupId }) { g in
            Button(g.name) {
              Task {
                await viewModel.copyPick(from: g.group_id)
                showCopyPicksSheet = false
              }
            }
            .disabled(viewModel.copyingPicks)
          }
        }
      }
      .navigationTitle("Copy pick")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { showCopyPicksSheet = false }
        }
      }
    }
  }

  /// Error / loading / empty states, shown as one row under the bar so the
  /// pinned bar (sport + week menus) stays usable in every state.
  @ViewBuilder private var stateMessage: some View {
    if let e = viewModel.errorText {
      VStack(spacing: BoldTheme.Space.s2) {
        Text("Couldn't load games").font(BoldTheme.TypeRole.title(20))
        Text(e).font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
        Button("Try again") { Task { await viewModel.loadInitial() } }
          .buttonStyle(SupSecondaryButtonStyle(fullWidth: false))
          .padding(.top, BoldTheme.Space.s2)
      }
      .foregroundColor(BoldTheme.Colors.text)
      .padding(BoldTheme.Space.s6)
      .frame(maxWidth: .infinity)
    } else if viewModel.isLoading && viewModel.games.isEmpty {
      ProgressView("Loading games…")
        .tint(BoldTheme.Colors.text)
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.textDim)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    } else if viewModel.games.isEmpty {
      emptyText("No games for this week yet.")
    } else if viewModel.visibleGames.isEmpty {
      // Games exist for the week but every CFB one is still hidden
      // pending a line -- distinct from the "nothing scheduled" case
      // above so this doesn't read as a bug.
      emptyText("Lines haven't posted for this week yet. Check back soon.")
    } else if filteredGames.isEmpty {
      emptyText("No games match “\(searchQuery)”.")
    }
  }

  private func emptyText(_ t: String) -> some View {
    Text(verbatim: t)
      .font(BoldTheme.Fonts.body(15))
      .foregroundColor(BoldTheme.Colors.textDim)
      .multilineTextAlignment(.center)
      .padding(.horizontal, BoldTheme.Space.s6)
      .padding(.top, 80)
      .frame(maxWidth: .infinity)
  }

  private var showSlate: Bool {
    viewModel.errorText == nil && !(viewModel.isLoading && viewModel.games.isEmpty) && !filteredGames.isEmpty
  }

  /// One scroll for the whole screen, like the web (de-slop #14): only the
  /// slim bar is pinned; the note, banners and every day card scroll.
  private var slate: some View {
    ScrollViewReader { proxy in
      List {
        Group {
          if showSlate && viewModel.selectedWeek == viewModel.currentWeek {
            selectHint
          } else {
            Color.clear.frame(height: BoldTheme.Space.s3)
          }
          groupPicker
          groupModeBanner
          if viewModel.selectedWeek < viewModel.currentWeek {
            pastWeekNote
          }
          stateMessage
        }
        .plainListRow()

        if showSlate {
          // Each day's header is a pinned section header (round 2): it
          // sticks under the filter bar and the next day's pushes it off.
          ForEach(dayGroups) { day in
            Section {
              ForEach(day.games) { g in
                gameRow(g, day: day)
              }
              Color.clear.frame(height: BoldTheme.Space.cardGap).plainListRow()
            } header: {
              dayHeader(day.dateLabel)
            }
            .id(day.id)
          }
        }
      }
      .listStyle(.plain)
      // No extra gap above each pinned day header; the 12pt spacer row
      // at the end of each day is the card gap.
      .listSectionSpacing(0)
      .environment(\.defaultMinListHeaderHeight, 0)
      .environment(\.defaultMinListRowHeight, 0)
      .scrollContentBackground(.hidden)
      .background(BoldTheme.Colors.bgPage)
      .scrollDismissesKeyboard(.immediately)
      // Directly on the List: iOS 26's top scroll-edge fade otherwise
      // washes out the pinned day header.
      .hardTopScrollEdge()
      .safeAreaInset(edge: .top, spacing: 0) { topBar }
      .refreshable {
        try? await viewModel.loadGames()
        try? await viewModel.loadExistingPick()
      }
      .sheet(item: $tappedGame) { g in
        PickCardSheet(
          game: g,
          logoFor: { id in viewModel.logoURL(for: id) },
          isCurrentPick: viewModel.selectedGameId == g.id,
          hasOtherPick: viewModel.selectedGameId != nil && viewModel.selectedGameId != g.id,
          isPro: isPro,
          watchEnabled: watchEnabled && viewModel.espnIds[g.id] != nil,
          watchLinks: viewModel.watchLinks(for: g),
          checkLine: { shown in await viewModel.recheckLine(for: shown) },
          onLock: { locked in await viewModel.pickUnderdog(for: locked, haptic: false) },
          onClear: { await viewModel.clearPickForWeek() }
        )
        // Fresh card per game: its @State (`shown`) is seeded from `game`,
        // so a quick dismiss-then-tap on another row must not reuse it.
        .id(g.id)
      }
      // A week spans both already-played and upcoming days -- opening on
      // the earliest day means scrolling past everything already final
      // just to reach today's or the next live game. Jump straight to
      // the first day that's today or later; if the whole week's in the
      // past (last week's tab), land on the most recent day instead of
      // the oldest.
      .task(id: targetDayId) {
        if consumeRequestedGame(proxy) { return }
        guard let targetDayId, searchQuery.isEmpty else { return }
        proxy.scrollTo(targetDayId, anchor: .top)
      }
      // Live ticker tap: go to that game's week, then scroll to its row.
      .onChange(of: appState.requestedGame) { _, _ in _ = consumeRequestedGame(proxy) }
      .onChange(of: viewModel.games.map(\.id)) { _, _ in _ = consumeRequestedGame(proxy) }
    }
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Handles appState.requestedGame once its sport is showing. Returns
  /// true when it scrolled.
  private func consumeRequestedGame(_ proxy: ScrollViewProxy) -> Bool {
    guard let r = appState.requestedGame, r.sport == viewModel.sport else { return false }
    if let w = r.week, w != viewModel.selectedWeek {
      viewModel.selectedWeek = w
      return false
    }
    guard viewModel.games.contains(where: { $0.id == r.id }) else { return false }
    searchQuery = ""
    withAnimation { proxy.scrollTo(r.id, anchor: .center) }
    appState.requestedGame = nil
    return true
  }

  private func gameRow(_ g: Game, day: DayGroup) -> some View {
    let isLast = g.id == day.games.last?.id
    let isPick = viewModel.selectedGameId == g.id
    let pickable = viewModel.canPick(g)
    return GameRowView(
      game: g,
      logoFor: { id in viewModel.logoURL(for: id) },
      isSelected: isPick,
      isFirstInDay: false,
      isLastInDay: isLast,
      // Pro only: the first linked network as a middle-column capsule.
      watch: isPro && watchEnabled ? viewModel.watchLinks(for: g).first(where: { $0.url != nil }) : nil
    )
    .contentShape(Rectangle())
    // Tap is the other way in: opens the pick card.
    .onTapGesture {
      guard viewModel.canPick(g) else { return }
      tappedGame = g
    }
    .clipShape(GameRowView.cardShape(isLastInDay: isLast))
    // The system list swipe, not a custom drag on every row: 1.3.5's
    // per-row DragGesture made scrolling lag on real phones.
    // Picked row: "Clear pick" until it locks. Others: "Pick {Dog} +N".
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if isPick {
        if pickable {
          Button("Clear pick") { Task { await viewModel.clearPickForWeek() } }
            .tint(Color(hex: 0x8E8E93))
        }
      } else if pickable {
        Button(viewModel.swipeActionLabel(for: g)) { Task { await viewModel.pickUnderdog(for: g) } }
          .tint(BoldTheme.Colors.green)
      }
    }
    .listRowInsets(EdgeInsets(top: 0, leading: BoldTheme.Space.margin, bottom: 0, trailing: BoldTheme.Space.margin))
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .id(g.id)
  }

  /// "FAVORITE · Tuesday, Oct 20 · UNDERDOG": the top strip of each day's
  /// card (de-slop #15) and a pinned section header. A full-width page-
  /// colour fill sits behind the card strip so rows never show through
  /// while it's pinned.
  private func dayHeader(_ dateLabel: String) -> some View {
    HStack {
      Text("FAVORITE").frame(maxWidth: .infinity, alignment: .leading)
      Text(dateLabel)
        .font(BoldTheme.Fonts.body(14, weight: .semibold))
        .tracking(0)
        .foregroundColor(BoldTheme.Colors.text)
        .lineLimit(1)
        .fixedSize()
      Text("UNDERDOG").frame(maxWidth: .infinity, alignment: .trailing)
    }
    .font(BoldTheme.TypeRole.label(10))
    .tracking(1)
    .foregroundColor(BoldTheme.Colors.textDim)
    .padding(.vertical, BoldTheme.Space.s3)
    .padding(.horizontal, BoldTheme.Space.cardPad)
    .background(
      UnevenRoundedRectangle(topLeadingRadius: BoldTheme.Radius.card, topTrailingRadius: BoldTheme.Radius.card, style: .continuous)
        .fill(BoldTheme.Colors.card)
    )
    .padding(.horizontal, BoldTheme.Space.margin)
    .frame(maxWidth: .infinity)
    // Page fill reaches a little above the strip (under the opaque bar),
    // so no sliver of a row can show between bar and pinned header.
    .background(BoldTheme.Colors.bgPage.padding(.top, -6))
    .listRowInsets(EdgeInsets())
    .textCase(nil)
  }

  // ── Slim pinned bar: "CFB ▾" (sport menu) · "Week 8 ▾" · search ──────
  @State private var searchOpen = false
  @FocusState private var searchFocused: Bool

  private var hpOptions: [HpSport] { HpSport.allCases.filter { featureFlags.isVisible($0.flag) } }

  private var topBar: some View {
    VStack(spacing: BoldTheme.Space.s2) {
      HStack(spacing: BoldTheme.Space.s2) {
        Menu {
          sportButton("CFB", game: .cfb)
          sportButton("Pro Ball", game: .nfl)
          sportButton("Pickems", game: .pickems)
          ForEach(hpOptions) { hp in
            Button(hp.name) { appState.goToHoopsPucks(hp) }
          }
        } label: {
          HStack(spacing: 4) {
            Text(viewModel.sport == "cfb" ? "CFB" : "PRO BALL")
              .font(BoldTheme.Fonts.display(30))
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .heavy))
          }
          .foregroundColor(BoldTheme.Colors.text)
        }
        .accessibilityLabel("Sport: \(viewModel.sport == "cfb" ? "CFB" : "Pro Ball")")

        if !viewModel.availableWeeks.isEmpty {
          Menu {
            ForEach(viewModel.availableWeeks.reversed(), id: \.self) { w in
              Button {
                viewModel.selectedWeek = w
              } label: {
                if w == viewModel.selectedWeek {
                  Label("Week \(formatWeekLabel(w))", systemImage: "checkmark")
                } else {
                  Text(verbatim: "Week \(formatWeekLabel(w))" + (w == viewModel.currentWeek ? " (this week)" : ""))
                }
              }
            }
          } label: {
            HStack(spacing: 4) {
              Text(verbatim: "Week \(formatWeekLabel(viewModel.selectedWeek))")
              Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy))
            }
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(BoldTheme.Colors.card))
          }
        }

        Spacer(minLength: 0)

        Button {
          withAnimation(.easeOut(duration: 0.2)) {
            searchOpen.toggle()
            if !searchOpen { searchQuery = "" }
          }
          searchFocused = searchOpen
        } label: {
          Image(systemName: searchOpen ? "xmark" : "magnifyingglass")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
            .frame(width: 36, height: 36)
            .background(Circle().fill(BoldTheme.Colors.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(searchOpen ? "Close search" : "Search teams")
      }
      if searchOpen {
        searchField
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
      LiveTickerStrip()
      pinnedPickBar
    }
    .animation(.easeOut(duration: 0.2), value: viewModel.selectedGameId)
    .padding(.horizontal, BoldTheme.Space.margin)
    .padding(.top, BoldTheme.Space.s2)
    .padding(.bottom, 10)
    // Opaque (round 3): with sticky day headers right under it, a frosted
    // bar let rows bleed through the band between bar and header.
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea(edges: .top))
    .overlay(alignment: .bottom) {
      Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
    }
  }

  private func sportButton(_ title: String, game: CurrentGame) -> some View {
    Button {
      appState.hpSport = nil
      appState.currentGame = game
    } label: {
      if appState.hpSport == nil && appState.currentGame == game {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }

  private var targetDayId: String? {
    let todayStart = Calendar.current.startOfDay(for: Date())
    return dayGroups.first(where: { ($0.games.first?.startTime ?? .distantPast) >= todayStart })?.id
      ?? dayGroups.last?.id
  }

  // Games in one week span multiple calendar days -- each day is its own
  // flat card with the FAVORITE · day · UNDERDOG header inside it.
  private struct DayGroup: Identifiable {
    let id: String
    let dateLabel: String
    let games: [Game]
  }

  private var dayGroups: [DayGroup] {
    var order: [String] = []
    var byDay: [String: [Game]] = [:]
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "EEEE, MMM d"

    for g in filteredGames {
      let key = Calendar.current.startOfDay(for: g.startTime).description
      if byDay[key] == nil { order.append(key); byDay[key] = [] }
      byDay[key]?.append(g)
    }

    return order.compactMap { key in
      guard let games = byDay[key], let first = games.first else { return nil }
      return DayGroup(id: key, dateLabel: dayFormatter.string(from: first.startTime), games: games)
    }
  }

  var body: some View {
    ZStack {
      slate
      // A fresh trigger only fires on a just-now successful pick (see
      // pickCelebrationTrigger's doc comment).
      // No confetti with Reduce Motion on.
      if let trigger = viewModel.pickCelebrationTrigger, !reduceMotion {
        ConfettiView(trigger: trigger, count: 50)
      }
    }
    // Toast floats above the tab bar (it sits inside the safe area).
    .overlay(alignment: .bottom) {
      if let msg = viewModel.toastMessage {
        Text(msg)
          .font(BoldTheme.Fonts.body(14, weight: .semibold))
          .foregroundColor(textOnGreen)
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(Capsule().fill(BoldTheme.Colors.green))
          .padding(.bottom, BoldTheme.Space.s3)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: viewModel.toastMessage)
    .onChange(of: viewModel.selectedWeek) {
      Task {
        async let pick: Void? = try? viewModel.loadExistingPick()
        try? await viewModel.loadGames()
        _ = await pick
      }
    }
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .task {
      // Consume the sport hand-off from Home's "MAKE YOUR PICK" tap, if any,
      // so this screen lands on whichever sport was selected there instead
      // of always resetting to CFB.
      if let requested = appState.requestedSport {
        viewModel.sport = requested
        appState.requestedSport = nil
        appState.currentGame = requested == "nfl" ? .nfl : .cfb
      } else if appState.currentGame == .nfl || appState.currentGame == .cfb {
        // No hand-off: land on whatever the shared switcher says.
        viewModel.sport = appState.currentGame.rawValue
      }
      viewModel.watchEnabled = watchEnabled
      await viewModel.loadInitial()
    }
    // watch_links can load (or the admin check land) after the first fetch.
    .onChange(of: watchEnabled) { _, on in
      viewModel.watchEnabled = on
      Task { await viewModel.loadWatch() }
    }
    // .task only runs once per view identity, which persists across tab
    // switches (StateObject) -- this catches later hand-offs from Home too,
    // e.g. the user already had Games open, then tapped Home's CTA again
    // with the other sport selected.
    .onChange(of: appState.requestedSport) { _, requested in
      guard let requested else { return }
      appState.requestedSport = nil
      appState.currentGame = requested == "nfl" ? .nfl : .cfb
      Task { await viewModel.switchSport(to: requested) }
    }
    // The shared GameSwitcher (here or on another tab) changed sport.
    // Pickems swaps this whole tab to PickemsView (see MainTabView).
    .onChange(of: appState.currentGame) { _, game in
      guard game == .cfb || game == .nfl, game.rawValue != viewModel.sport else { return }
      Task { await viewModel.switchSport(to: game.rawValue) }
    }
    .onChange(of: viewModel.activeGroupId) { _, _ in
      Task { try? await viewModel.loadExistingPick() }
    }
  }
}

private extension View {
  /// A full-bleed List row with no background, inset or separator -- for
  /// the note, banners and spacers that scroll with the slate.
  func plainListRow() -> some View {
    self
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
  }
}
