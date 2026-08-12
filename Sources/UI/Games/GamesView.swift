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
      #if DEBUG
      print("[pickUnderdog] SUCCESS, toast=\(toastMessage ?? "")")
      #endif
    } catch {
      selectedGameId = previous
      flashToast("Couldn’t save pick: \(error.localizedDescription)")
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
      flashToast("Couldn’t clear: \(error.localizedDescription)")
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

  private var header: some View {
    HStack {
      SupIcon(variant: .monogram)
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      Spacer()
      Menu {
        ForEach(viewModel.availableWeeks, id: \.self) { wk in
          Button { viewModel.selectedWeek = wk } label: {
            Label("Week \(wk)", systemImage: wk == viewModel.selectedWeek ? "checkmark" : "circle")
          }
        }
      } label: {
        Label("Week \(viewModel.selectedWeek)", systemImage: "calendar")
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
            AsyncImage(url: viewModel.logoURL(for: g.derivedUnderdogTeamId)) { phase in
              switch phase {
              case .success(let img): img.resizable().scaledToFit().padding(5)
              default:
                Image(systemName: "checkmark")
                  .font(.system(size: 16, weight: .bold))
                  .foregroundColor(BoldTheme.Colors.text)
              }
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
            Text(verbatim: "Loses by fewer than \(String(format: "%.1f", sp)), or wins outright, and you bank it.")
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
    } else {
      List {
        Section {
          ForEach(viewModel.games) { g in
            GameRowView(
              game: g,
              logoFor: { id in viewModel.logoURL(for: id) },
              isSelected: viewModel.selectedGameId == g.id
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              if viewModel.selectedGameId == g.id {
                Button("Clear pick") {
                  Task { await viewModel.clearPickForWeek() }
                }.tint(.gray)
              } else {
                Button("Pick this upset") {
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
          columnHeader
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(BoldTheme.Colors.bgPage)
    }
  }

  // Pinned column labels -- List's .plain style floats section headers at
  // the top on scroll (native UITableView.Style.plain behavior), so this
  // stays visible above the rows instead of scrolling away with them.
  private var columnHeader: some View {
    HStack {
      Text("FAVORITE")
      Spacer()
      Text("UNDERDOG")
    }
    .font(BoldTheme.Fonts.mono(11))
    .tracking(0.9)
    .foregroundColor(BoldTheme.Colors.textFaint)
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
