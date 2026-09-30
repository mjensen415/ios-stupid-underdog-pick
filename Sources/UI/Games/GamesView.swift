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

  func loadInitial() async {
    isLoading = true; errorText = nil
    defer { isLoading = false }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: sport)
      season = ctx.season
      selectedWeek = ctx.week
      currentWeek = ctx.week
      availableWeeks = try await GamesService(client: client).distinctWeeks(forSeason: season, sport: sport)
      // Inline team logo fetch to avoid TeamService dependency
      struct T: Decodable { let id: UUID; let logo_url: String? }
      let teamRes = try await client
        .from("teams")
        .select("id, logo_url")
        .execute()
      let teams = try JSONDecoder().decode([T].self, from: teamRes.data)
      logoMap = Dictionary(uniqueKeysWithValues: teams.map { t in (t.id, t.logo_url.flatMap { URL(string: $0) }) }).compactMapValues { $0 }
      myGroups = (try? await GroupsService(client: client).fetchMyGroups()) ?? []
      if let activeGroupId, !underdogGroups.contains(where: { $0.group_id == activeGroupId }) {
        self.activeGroupId = nil
      }
      try await loadGames()
      try await loadExistingPick()
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
      return selectedGameId != nil && selectedGameId != g.id ? "Change to this upset" : "Pick this upset"
    }
    if currentPickIsLocked && g.id != selectedGameId { return "Your pick is locked" }
    if g.status == "in_progress" { return "Game Live" }
    if g.status == "final" { return "Game Over" }
    return "Locked"
  }

  func pickUnderdog(for g: Game) async {
    #if DEBUG
    print("[pickUnderdog] BUTTON FIRED for \(g.awayTeam ?? "?") @ \(g.homeTeam ?? "?"), canPick=\(canPick(g))")
    #endif
    guard canPick(g) else { return }
    guard let pickedId = g.derivedUnderdogTeamId else {
      #if DEBUG
      print("[pickUnderdog] BLOCKED: derivedUnderdogTeamId is nil")
      #endif
      return
    }
    let previous = selectedGameId
    let previousPick = myPick
    selectedGameId = g.id
    myPick = nil
    savingPick = true; defer { savingPick = false }
    do {
      _ = try await PicksService(client: client)
        .upsertPick(gameId: g.id, pickedTeamId: pickedId, season: season, week: selectedWeek, groupId: activeGroupId)
      flashToast("Picked \(g.awayTeam ?? "") @ \(g.homeTeam ?? "")")
      Haptics.success()
      pickCelebrationTrigger = UUID()
      // They just used the swipe gesture successfully -- the hint banner
      // has nothing left to teach them. Written directly to UserDefaults
      // (shared key with GamesView's @AppStorage) since the ViewModel has
      // no view-level binding to flip.
      UserDefaults.standard.set(true, forKey: GamesView.swipeHintDefaultsKey)
      #if DEBUG
      print("[pickUnderdog] SUCCESS, toast=\(toastMessage ?? "")")
      #endif
    } catch {
      selectedGameId = previous
      myPick = previousPick
      flashToast("Couldn’t save pick: \(friendlyPickErrorMessage(error))")
      #if DEBUG
      print("[pickUnderdog] SAVE FAILED: \(error)")
      #endif
    }
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
  @AppStorage(GamesView.swipeHintDefaultsKey) private var hasSeenSwipeHint = false
  @State private var tappedGame: Game?

  private var header: some View {
    HStack {
      SupIcon(variant: .monogram)
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      Spacer()
      // CFB and Pro Ball run on separate week numbering (offset by
      // roughly a week), so the sport rides along with the week number.
      // Picking the week happens in the pill row below.
      Label("\(viewModel.sport == "cfb" ? "CFB" : "PRO BALL") · Week \(formatWeekLabel(viewModel.selectedWeek))", systemImage: "calendar")
        .font(BoldTheme.Fonts.body(14, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.goldDeep)
        .onChange(of: viewModel.selectedWeek) {
          Task {
            try? await viewModel.loadGames()
            try? await viewModel.loadExistingPick()
          }
        }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .background(BoldTheme.Colors.bgPage)
  }

  // The picked team's row already tints gold + gets a checkmark badge
  // (GameRowView.isSelected) -- this banner is the "which game, at a
  // glance, without scrolling to find the tinted row" signal on top.
  private var pickedGame: Game? {
    guard let id = viewModel.selectedGameId else { return nil }
    return viewModel.games.first { $0.id == id }
  }

  @ViewBuilder
  private var pickedBanner: some View {
    if let g = pickedGame {
      // The team actually picked (a Pro Ball line can move after the pick,
      // even flipping who the underdog is), scored on its locked line.
      let savedPick = viewModel.myPick?.game_id == g.id ? viewModel.myPick : nil
      let pickedTeamId = savedPick?.picked_team_id ?? g.derivedUnderdogTeamId
      let underdogIsHome = pickedTeamId != nil && pickedTeamId == g.homeTeamId
      let underdogName = underdogIsHome ? (g.homeTeam ?? "Home") : (g.awayTeam ?? "Away")
      let favoriteName = underdogIsHome ? (g.awayTeam ?? "Away") : (g.homeTeam ?? "Home")
      let bankSpread: Double? = savedPick.map { $0.winPoints(on: g) } ?? g.underdogSpread
      let lineNote = savedPick?.lineNote(on: g)
      HStack(spacing: 14) {
        Circle()
          .fill(BoldTheme.Colors.gold)
          .frame(width: 40, height: 40)
          .overlay(
            RetryingAsyncImage(url: viewModel.logoURL(for: pickedTeamId)) { img in
              img.resizable().scaledToFit().padding(5)
            } placeholder: {
              Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(BoldTheme.Colors.text)
            }
          )
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "WEEK \(formatWeekLabel(viewModel.selectedWeek)) PICK")
            .font(BoldTheme.Fonts.mono(10, weight: .semibold))
            .foregroundColor(textOnGreen.opacity(0.7))
          HStack(spacing: 6) {
            Text(underdogName.uppercased())
              .font(BoldTheme.Fonts.display(20))
              .foregroundColor(textOnGreen)
            if let sp = bankSpread {
              Text(verbatim: "+\(String(format: "%.1f", sp))")
                .font(BoldTheme.Fonts.display(20))
                .foregroundColor(BoldTheme.Colors.gold)
            }
          }
          Text(verbatim: "vs \(favoriteName)")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(textOnGreen.opacity(0.75))
          // Once the game's decided, say what happened instead of what could.
          if let pickedTeamId, g.status == "final" {
            let won = g.outcome(forPickedTeamId: pickedTeamId) == .win
            Text(verbatim: won
                 ? (bankSpread.map { "Won outright — banked \(String(format: "%.1f", $0)) points." } ?? "Won outright.")
                 : "Lost — no points this week.")
              .font(BoldTheme.Fonts.body(11, weight: won ? .semibold : .regular))
              .foregroundColor(won ? BoldTheme.Colors.gold : textOnGreen.opacity(0.65))
              .padding(.top, 2)
          } else if g.status == "in_progress" {
            Text("Live now.")
              .font(BoldTheme.Fonts.body(11, weight: .semibold))
              .foregroundColor(textOnGreen.opacity(0.8))
              .padding(.top, 2)
          } else if let sp = bankSpread {
            Text(verbatim: "Wins outright and you bank \(String(format: "%.1f", sp)) points.")
              .font(BoldTheme.Fonts.body(11))
              .foregroundColor(textOnGreen.opacity(0.65))
              .padding(.top, 2)
          }
          if let lineNote {
            Text(lineNote)
              .font(BoldTheme.Fonts.body(11, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.gold)
          }
        }
        Spacer()
        if let shareImage, let sp = bankSpread {
          // No singular `item: Image` initializer exists on ShareLink --
          // only items:/preview: (Image conforms to Transferable, so a
          // one-element array is the correct way to share a single image).
          ShareLink(
            items: [shareImage],
            preview: { img in SharePreview(Text(verbatim: "\(underdogName) +\(String(format: "%.1f", sp))"), image: img) }
          ) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(textOnGreen)
          }
        }
      }
      .padding(16)
      .background(BoldTheme.Colors.green)
      .cornerRadius(10)
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
      .task(id: g.id) {
        guard let sp = bankSpread else { shareImage = nil; return }
        if let uiImage = renderShareCardImage(dogName: underdogName, spread: sp, favoriteName: favoriteName) {
          shareImage = Image(uiImage: uiImage)
        }
      }
    }
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
      let name = (pickedIsHome ? g.homeTeam : g.awayTeam) ?? "Your pick"
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
        + Text(verbatim: spread.map { " +\(String(format: "%.1f", $0))" } ?? "")
          .font(BoldTheme.Fonts.mono(12, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.goldDeep)
        Spacer(minLength: 6)
        switch outcome {
        case .win:
          Text(verbatim: spread.map { "WON +\(String(format: "%.1f", $0))" } ?? "WON")
            .font(BoldTheme.Fonts.mono(11, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(BoldTheme.Colors.gold)
            .clipShape(Capsule())
        case .loss:
          Text("MISS")
            .font(BoldTheme.Fonts.mono(11, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textDim)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(BoldTheme.Colors.track)
            .clipShape(Capsule())
        case .pending:
          Text(g.status == "in_progress" ? "LIVE" : "PENDING")
            .font(BoldTheme.Fonts.mono(11, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      .lineLimit(1)
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 20)
      .padding(.bottom, 10)
    } else if !viewModel.games.isEmpty && viewModel.selectedGameId == nil {
      HStack(spacing: 8) {
        Image(systemName: "minus.circle")
          .foregroundColor(BoldTheme.Colors.textFaint)
        Text(verbatim: "No pick in Week \(week).")
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer()
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 20)
      .padding(.bottom, 10)
    }
  }

  private var tapDialogTitle: String {
    guard let g = tappedGame else { return "" }
    if viewModel.selectedGameId == g.id { return "Your pick" }
    let dog = g.derivedUnderdogTeamId == g.homeTeamId ? g.homeTeam : g.awayTeam
    guard let sp = g.underdogSpread else { return dog ?? "Pick this upset?" }
    let n = sp == sp.rounded() ? String(format: "%.0f", sp) : String(format: "%.1f", sp)
    return "\(dog ?? "Underdog") +\(n)"
  }

  @ViewBuilder
  private var swipeHintBanner: some View {
    if !hasSeenSwipeHint {
      HStack(spacing: 10) {
        Image(systemName: "hand.draw.fill")
          .foregroundColor(BoldTheme.Colors.goldDeep)
        Text("Tap a game (or swipe left) to lock in that underdog.")
          .font(BoldTheme.Fonts.body(13, weight: .medium))
          .foregroundColor(BoldTheme.Colors.text)
        Spacer()
        Button {
          withAnimation { hasSeenSwipeHint = true }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      .padding(12)
      .background(BoldTheme.Colors.gold.opacity(0.12))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BoldTheme.Colors.goldDeep.opacity(0.3), lineWidth: 1))
      .cornerRadius(10)
      .padding(.horizontal, 20)
      .padding(.bottom, 8)
      .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundColor(BoldTheme.Colors.textFaint)
        .font(.system(size: 14, weight: .medium))
      TextField("Search teams", text: $searchQuery)
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
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(Color(hex: 0x16241B).opacity(0.07))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .cornerRadius(10)
    .padding(.horizontal, 20)
    .padding(.bottom, 10)
  }

  // Matches either team's full or short name -- a search for "OSU" alone
  // wouldn't hit anything useful given how inconsistently team short names
  // are populated, so this sticks to substring matching on the names
  // actually shown on the row.
  private var filteredGames: [Game] {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return viewModel.visibleGames }
    return viewModel.visibleGames.filter { g in
      [g.homeTeam, g.awayTeam].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
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
          Text(activeGroupName ?? "My Shared Picks")
            .font(BoldTheme.Fonts.body(12.5, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
          Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(viewModel.activeGroupId != nil ? BoldTheme.Colors.gold.opacity(0.16) : BoldTheme.Colors.track)
        .overlay(Capsule().strokeBorder(viewModel.activeGroupId != nil ? BoldTheme.Colors.goldDeep : .clear, lineWidth: 1))
        .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 20)
      .padding(.bottom, 10)
      .confirmationDialog("Picking for", isPresented: $showGroupPicker, titleVisibility: .visible) {
        Button("My Shared Picks") { viewModel.activeGroupId = nil }
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
            .foregroundColor(BoldTheme.Colors.goldDeep)
          Button("Reset to shared") { Task { await viewModel.resetToSharedPick() } }
            .font(BoldTheme.Fonts.body(11, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      .padding(12)
      .background(BoldTheme.Colors.gold.opacity(0.1))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.goldDeep, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 20)
      .padding(.bottom, 10)
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
          Button("My Shared Picks") {
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
      .navigationTitle("Copy Pick")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { showCopyPicksSheet = false }
        }
      }
    }
  }

  @ViewBuilder private var content: some View {
    if let e = viewModel.errorText {
      VStack(spacing: 8) {
        Text("Error loading games").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
        Text(e).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
        Button("Retry") { Task { await viewModel.loadInitial() } }
          .foregroundColor(BoldTheme.Colors.goldDeep)
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(BoldTheme.Colors.bgPage)
    } else if viewModel.isLoading && viewModel.games.isEmpty {
      ProgressView("Loading games…")
        .tint(BoldTheme.Colors.gold)
        .foregroundColor(BoldTheme.Colors.textDim)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoldTheme.Colors.bgPage)
    } else if viewModel.games.isEmpty {
      Text("No games for this week yet.")
        .foregroundColor(BoldTheme.Colors.textDim)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoldTheme.Colors.bgPage)
    } else if viewModel.visibleGames.isEmpty {
      // Games exist for the week but every CFB one is still hidden
      // pending a line -- distinct from the "nothing scheduled" case
      // above so this doesn't read as a bug.
      Text("Lines haven't posted for this week yet. Check back soon.")
        .foregroundColor(BoldTheme.Colors.textDim)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoldTheme.Colors.bgPage)
    } else if filteredGames.isEmpty {
      Text(verbatim: "No games match “\(searchQuery).”")
        .foregroundColor(BoldTheme.Colors.textDim)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoldTheme.Colors.bgPage)
    } else {
      ScrollViewReader { proxy in
        List {
          ForEach(dayGroups) { day in
            Section {
              ForEach(day.games) { g in
                GameRowView(
                  game: g,
                  logoFor: { id in viewModel.logoURL(for: id) },
                  isSelected: viewModel.selectedGameId == g.id,
                  isFirstInDay: g.id == day.games.first?.id,
                  isLastInDay: g.id == day.games.last?.id
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                  if viewModel.selectedGameId == g.id {
                    // Once the picked game has locked (kickoff passed, or
                    // it's live/final), the pick is final -- the server
                    // rejects a clear anyway (see clear_weekly_pick's
                    // PICKS_LOCKED_AFTER_KICKOFF guard), so don't show a
                    // swipe action that can only ever fail. Mirrors web's
                    // BoldGreenBanner CHANGE-button treatment.
                    if viewModel.canPick(g) {
                      Button("Clear pick") {
                        Task { await viewModel.clearPickForWeek() }
                      }.tint(.gray)
                    }
                  } else {
                    Button(viewModel.swipeActionLabel(for: g)) {
                      Task { await viewModel.pickUnderdog(for: g) }
                    }
                    // swipeActions buttons always render white label text with
                    // .tint() only coloring the background -- goldDeep (not the
                    // bright brand gold) is what gives that white text real
                    // contrast here.
                    .tint(viewModel.canPick(g) ? BoldTheme.Colors.goldDeep : .gray)
                    .disabled(!viewModel.canPick(g))
                  }
                }
                // Tap is the second way in (swipe stays): opens a confirm
                // sheet with the same actions the swipe would offer.
                .contentShape(Rectangle())
                .onTapGesture {
                  guard viewModel.canPick(g) else { return }
                  tappedGame = g
                }
              }
            } header: {
              columnHeader(dateLabel: day.dateLabel)
            }
            .id(day.id)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BoldTheme.Colors.bgPage)
        .dismissKeyboardOnTap()
        .confirmationDialog(
          tapDialogTitle,
          isPresented: Binding(get: { tappedGame != nil }, set: { if !$0 { tappedGame = nil } }),
          titleVisibility: .visible,
          presenting: tappedGame
        ) { g in
          if viewModel.selectedGameId == g.id {
            Button("Clear pick", role: .destructive) {
              Task { await viewModel.clearPickForWeek() }
            }
          } else {
            Button(viewModel.swipeActionLabel(for: g)) {
              Task { await viewModel.pickUnderdog(for: g) }
            }
          }
          Button("Cancel", role: .cancel) {}
        } message: { g in
          if viewModel.selectedGameId != g.id, g.sport == "nfl" {
            Text("Pro Ball lines move during the week. Your line locks in when you pick.")
          }
        }
        // A week spans both already-played and upcoming days -- opening on
        // the earliest day means scrolling past everything already final
        // just to reach today's or the next live game. Jump straight to
        // the first day that's today or later; if the whole week's in the
        // past (last week's tab), land on the most recent day instead of
        // the oldest.
        .task(id: targetDayId) {
          guard let targetDayId else { return }
          proxy.scrollTo(targetDayId, anchor: .top)
        }
      }
    }
  }

  private var targetDayId: String? {
    let todayStart = Calendar.current.startOfDay(for: Date())
    return dayGroups.first(where: { ($0.games.first?.startTime ?? .distantPast) >= todayStart })?.id
      ?? dayGroups.last?.id
  }

  // Games in one week span multiple calendar days -- grouping into one
  // Section per day (instead of a single flat list) gives each day its
  // own floating header as you scroll, matching List's .plain
  // sticky-header behavior, and makes it visually obvious where one day
  // ends and the next begins.
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
      return DayGroup(id: key, dateLabel: dayFormatter.string(from: first.startTime).uppercased(), games: games)
    }
  }

  // Pinned column labels -- List's .plain style floats section headers at
  // the top on scroll (native UITableView.Style.plain behavior), so this
  // stays visible above the rows instead of scrolling away with them.
  private func columnHeader(dateLabel: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(dateLabel)
        .font(BoldTheme.Fonts.mono(11, weight: .bold))
        .tracking(0.6)
        .foregroundColor(BoldTheme.Colors.text)
      HStack {
        Text("FAVORITE")
        Spacer()
        Text("UNDERDOG")
      }
      .font(BoldTheme.Fonts.mono(11))
      .tracking(0.9)
      .foregroundColor(BoldTheme.Colors.textFaint)
    }
    // Full-bleed and opaque: a plain List's section header otherwise gets
    // its own inset + default background, so the pinned header floated as
    // an inset grey box with white edges while rows scrolled under it. The
    // gap between days lives here (top padding) instead of a clear footer
    // that let the list background show through.
    .padding(.horizontal, 20)
    .padding(.top, 14)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(BoldTheme.Colors.bgPage)
    .overlay(alignment: .bottom) {
      Rectangle().fill(BoldTheme.Colors.border).frame(height: 1).padding(.horizontal, 12)
    }
    .listRowInsets(EdgeInsets())
    .textCase(nil)
  }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        header
        GameSwitcher()
          .padding(.horizontal, 20)
          .padding(.bottom, 10)
        groupPicker
        groupModeBanner
        if viewModel.availableWeeks.count > 1 {
          WeekPills(weeks: viewModel.availableWeeks, selected: $viewModel.selectedWeek)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        searchField
        swipeHintBanner
        if viewModel.selectedWeek < viewModel.currentWeek {
          pastWeekNote
        } else {
          pickedBanner
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        content
        if let msg = viewModel.toastMessage {
          Spacer()
          Text(msg)
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(textOnGreen)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(BoldTheme.Colors.green)
            .clipShape(Capsule())
            .shadow(radius: 2)
            .padding(.bottom, 12)
        }
      }
      // A fresh trigger only fires on a just-now successful pick (see
      // pickCelebrationTrigger's doc comment) -- this is iOS's fanfare
      // moment, the equivalent of web's confirmation-sheet celebration,
      // since the swipe-to-pick gesture here has no separate confirm step.
      if let trigger = viewModel.pickCelebrationTrigger {
        ConfettiView(trigger: trigger, count: 50)
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
      await viewModel.loadInitial()
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
