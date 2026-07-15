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

  private let client: SupabaseClient
  private var logoMap: [UUID: URL] = [:]

  init(client: SupabaseClient) { self.client = client }

  func logoURL(for id: UUID?) -> URL? {
    guard let id, let s = logoMap[id] else { return nil }
    return s
  }

  func loadInitial() async {
    isLoading = true; errorText = nil
    defer { isLoading = false }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext()
      season = ctx.season
      selectedWeek = ctx.week
      availableWeeks = try await GamesService(client: client).distinctWeeks(forSeason: season)
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

  func loadGames() async throws {
    isLoading = true; defer { isLoading = false }
    errorText = nil
    let svc = GamesService(client: client)
    games = try await svc.fetch(season: season, week: selectedWeek)
  }

  func loadExistingPick() async throws {
    if let pick = try await PicksService(client: client).myPick(season: season, week: selectedWeek) {
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
      toastMessage = "Picked \(g.awayTeam ?? "") @ \(g.homeTeam ?? "")"
      #if DEBUG
      print("[pickUnderdog] SUCCESS, toast=\(toastMessage ?? "")")
      #endif
    } catch {
      selectedGameId = previous
      toastMessage = "Couldn’t save pick: \(error.localizedDescription)"
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
      try await PicksService(client: client).clearPick(season: season, week: selectedWeek)
      toastMessage = "Pick cleared"
    } catch {
      selectedGameId = previous
      toastMessage = "Couldn’t clear: \(error.localizedDescription)"
    }
  }
}

struct GamesView: View {
  @StateObject var viewModel: GamesViewModel

  private var header: some View {
    HStack {
      Text("SUP").font(.title3.bold())
      Spacer()
      Menu {
        ForEach(viewModel.availableWeeks, id: \.self) { wk in
          Button { viewModel.selectedWeek = wk } label: {
            Label("Week \(wk)", systemImage: wk == viewModel.selectedWeek ? "checkmark" : "circle")
          }
        }
      } label: {
        Label("Week \(viewModel.selectedWeek)", systemImage: "calendar")
          .font(.subheadline.bold())
      }
        .onChange(of: viewModel.selectedWeek) { _ in
          Task {
            try? await viewModel.loadGames()
            try? await viewModel.loadExistingPick()
          }
        }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  @ViewBuilder private var content: some View {
    if let e = viewModel.errorText {
      VStack(spacing: 8) {
        Text("Error loading games").font(.title3.bold())
        Text(e).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button("Retry") { Task { await viewModel.loadInitial() } }
      }.padding()
    } else if viewModel.isLoading && viewModel.games.isEmpty {
      ProgressView("Loading games…").frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if viewModel.games.isEmpty {
      Text("No games for this week yet.").foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .tint(viewModel.canPick(g) ? .blue : .gray)
                .disabled(!viewModel.canPick(g))
              }
            }
          }
        } header: {
          columnHeader
        }
      }
      .listStyle(.plain)
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
    .font(.caption.bold())
    .foregroundStyle(.secondary)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
    .textCase(nil)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      content
      if let msg = viewModel.toastMessage {
        Spacer()
        Text(msg)
          .font(.footnote)
          .padding(.horizontal, 12).padding(.vertical, 8)
          .background(.ultraThinMaterial)
          .clipShape(Capsule())
          .shadow(radius: 2)
          .padding(.bottom, 12)
      }
    }
    .task {
      await viewModel.loadInitial()
    }
  }
}
