import SwiftUI
import Supabase

@MainActor
final class GamesViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published var games: [Game] = []
  @Published var availableWeeks: [Int] = []
  @Published var selectedWeek: Int = 1
  @Published var season: Int = 2025
  @Published var selectedGameId: UUID? = nil
  @Published var savingPick = false
  @Published var toastMessage: String?
  @Published var sport: String = "cfb"
  /// Set to a fresh id only on a just-now successful pick (never on load),
  /// so GamesView can fire a one-shot confetti burst without re-celebrating
  /// every time the screen re-renders an existing pick.
  @Published var pickCelebrationTrigger: UUID?

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
      availableWeeks = try await GamesService(client: client).distinctWeeks(forSeason: season, sport: sport)
      // Inline team logo fetch to avoid TeamService dependency
      struct T: Decodable { let id: UUID; let logo_url: String? }
      let teamRes = try await client
        .from("teams")
        .select("id, logo_url")
        .execute()
      let teams = try JSONDecoder().decode([T].self, from: teamRes.data)
      logoMap = Dictionary(uniqueKeysWithValues: teams.map { t in (t.id, t.logo_url.flatMap { URL(string: $0) }) }).compactMapValues { $0 }
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
    if let pick = try await PicksService(client: client).myPick(season: season, week: selectedWeek, sport: sport) {
      selectedGameId = pick.game_id
    } else {
      selectedGameId = nil
    }
  }

  /// NFL lines are effectively guaranteed to post (just not synced yet at
  /// any given moment) -- NFL keeps showing every game, with GameRowView's
  /// muted "LINE TBD" treatment covering that brief gap. CFB is different:
  /// most of a week's slate is small-school matchups (Div II, Div III,
  /// NAIA) that never get a market line at all, at any point -- confirmed
  /// against real Week 1 data, 358 of 456 CFB games never had a spread,
  /// 116 of those were already final with still no line ever posted.
  /// Originally these stayed visible once locked/final (so a week's full
  /// slate of results stayed visible after the fact), but that just
  /// produced a wall of unpickable "--" final-score rows with no way to
  /// ever tell a dog from a favorite -- hide a CFB game once its kickoff
  /// has passed if it never got a line; still show it pre-kickoff since a
  /// line can still post before then.
  var visibleGames: [Game] {
    guard sport == "cfb" else { return games }
    return games.filter { g in
      g.derivedFavoriteTeamId != nil || (g.picksLocked != true && g.status != "final")
    }
  }

  func canPick(_ g: Game) -> Bool {
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
    if canPick(g) { return "Pick this upset" }
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
    selectedGameId = g.id
    savingPick = true; defer { savingPick = false }
    do {
      _ = try await PicksService(client: client)
        .upsertPick(gameId: g.id, pickedTeamId: pickedId, season: season, week: selectedWeek)
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
      flashToast("Couldn’t save pick: \(friendlyPickErrorMessage(error))")
      #if DEBUG
      print("[pickUnderdog] SAVE FAILED: \(error)")
      #endif
    }
  }

  func clearPickForWeek() async {
    let previous = selectedGameId
    selectedGameId = nil
    savingPick = true; defer { savingPick = false }
    do {
      try await PicksService(client: client).clearPick(season: season, week: selectedWeek, sport: sport)
      flashToast("Pick cleared")
    } catch {
      selectedGameId = previous
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

  // Picking here is a swipe-left gesture on the row (see .swipeActions
  // below) with no other on-screen affordance -- feedback showed people
  // land on this screen and don't discover it. One-time dismissible
  // banner, shown until dismissed or until they successfully make a pick
  // (whichever first -- see GamesViewModel.pickUnderdog).
  static let swipeHintDefaultsKey = "hasSeenSwipeToPickHint"
  @AppStorage(GamesView.swipeHintDefaultsKey) private var hasSeenSwipeHint = false

  private var header: some View {
    HStack {
      SupIcon(variant: .monogram)
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      Spacer()
      Menu {
        ForEach(viewModel.availableWeeks, id: \.self) { wk in
          Button { viewModel.selectedWeek = wk } label: {
            Label("Week \(formatWeekLabel(wk))", systemImage: wk == viewModel.selectedWeek ? "checkmark" : "circle")
          }
        }
      } label: {
        // CFB and Pro Ball run on separate week numbering (offset by
        // roughly a week), so the sport always rides along with the
        // week number here rather than leaving it to the sport toggle
        // below to imply -- otherwise switching sports and seeing the
        // week number change on its own reads as a bug, not a feature.
        Label("\(viewModel.sport == "cfb" ? "CFB" : "PRO BALL") · Week \(formatWeekLabel(viewModel.selectedWeek))", systemImage: "calendar")
          .font(BoldTheme.Fonts.body(14, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.goldDeep)
      }
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
      let underdogIsHome = g.derivedUnderdogTeamId != nil && g.derivedUnderdogTeamId == g.homeTeamId
      let underdogName = underdogIsHome ? (g.homeTeam ?? "Home") : (g.awayTeam ?? "Away")
      let favoriteName = underdogIsHome ? (g.awayTeam ?? "Away") : (g.homeTeam ?? "Home")
      HStack(spacing: 14) {
        Circle()
          .fill(BoldTheme.Colors.gold)
          .frame(width: 40, height: 40)
          .overlay(
            RetryingAsyncImage(url: viewModel.logoURL(for: g.derivedUnderdogTeamId)) { img in
              img.resizable().scaledToFit().padding(5)
            } placeholder: {
              Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(BoldTheme.Colors.text)
            }
          )
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text("YOUR PICK THIS WEEK")
            .font(BoldTheme.Fonts.mono(10, weight: .semibold))
            .foregroundColor(textOnGreen.opacity(0.7))
          HStack(spacing: 6) {
            Text(underdogName.uppercased())
              .font(BoldTheme.Fonts.display(20))
              .foregroundColor(textOnGreen)
            if let sp = g.underdogSpread {
              Text(verbatim: "+\(String(format: "%.1f", sp))")
                .font(BoldTheme.Fonts.display(20))
                .foregroundColor(BoldTheme.Colors.gold)
            }
          }
          Text(verbatim: "vs \(favoriteName)")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(textOnGreen.opacity(0.75))
          if let sp = g.underdogSpread {
            Text(verbatim: "Wins outright and you bank \(String(format: "%.1f", sp)) points.")
              .font(BoldTheme.Fonts.body(11))
              .foregroundColor(textOnGreen.opacity(0.65))
              .padding(.top, 2)
          }
        }
        Spacer()
        if let shareImage, let sp = g.underdogSpread {
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
        guard let sp = g.underdogSpread else { shareImage = nil; return }
        if let uiImage = renderShareCardImage(dogName: underdogName, spread: sp, favoriteName: favoriteName) {
          shareImage = Image(uiImage: uiImage)
        }
      }
    }
  }

  @ViewBuilder
  private var swipeHintBanner: some View {
    if !hasSeenSwipeHint {
      HStack(spacing: 10) {
        Image(systemName: "hand.draw.fill")
          .foregroundColor(BoldTheme.Colors.goldDeep)
        Text("Swipe left on a game to lock in that underdog.")
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

  private var sportToggle: some View {
    HStack(spacing: 4) {
      ForEach(["cfb", "nfl"], id: \.self) { s in
        let active = s == viewModel.sport
        Button {
          Task { await viewModel.switchSport(to: s) }
        } label: {
          Text(s == "cfb" ? "🏈 CFB" : "🏈 PRO BALL")
            .font(BoldTheme.Fonts.body(13, weight: .bold))
            .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? Color.white : Color.clear)
            .cornerRadius(10)
            .shadow(color: active ? Color(hex: 0x142A1C).opacity(0.14) : .clear, radius: 6, y: 3)
        }
      }
    }
    .padding(4)
    .background(Color(hex: 0x16241B).opacity(0.07))
    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .cornerRadius(13)
    .padding(.horizontal, 20)
    .padding(.bottom, 10)
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
              }
            } header: {
              columnHeader(dateLabel: day.dateLabel)
            } footer: {
              // Visible gap between one day's card and the next -- otherwise
              // adjoining cards' rounded bottom/top corners would touch with
              // no breathing room, reading as one broken shape instead of two.
              Color.clear.frame(height: 16).listRowInsets(EdgeInsets())
            }
            .id(day.id)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BoldTheme.Colors.bgPage)
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
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .background(BoldTheme.Colors.bgPage)
    .textCase(nil)
  }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        header
        sportToggle
        searchField
        swipeHintBanner
        pickedBanner
          .transition(.opacity.combined(with: .move(edge: .top)))
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
      Task { await viewModel.switchSport(to: requested) }
    }
  }
}
