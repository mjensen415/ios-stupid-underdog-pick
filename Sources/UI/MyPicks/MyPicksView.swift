import SwiftUI
import Supabase

struct MyPicksView: View {
  @Environment(\.supabaseClient) private var client
  @State private var season: Int = 0
  @State private var selectedWeek: Int = 1
  @State private var availableWeeks: [Int] = []
  @State private var games: [Game] = []
  @State private var logoMap: [UUID: URL] = [:]
  @State private var errorText: String?
  @State private var isLoading = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("MY PICKS").font(BoldTheme.Fonts.display(20)).tracking(0.6).foregroundColor(BoldTheme.Colors.text)
        Spacer()
        Menu {
          ForEach(availableWeeks, id: \.self) { wk in
            Button {
              selectedWeek = wk
            } label: {
              Label("Week \(wk)", systemImage: wk == selectedWeek ? "checkmark" : "circle")
            }
          }
        } label: {
          Label("Week \(selectedWeek)", systemImage: "calendar")
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.gold)
        }
        .onChange(of: selectedWeek) { _ in Task { await reload() } }
      }
      .padding(.horizontal).padding(.vertical, 8)
      .background(BoldTheme.Colors.bgPage)

      content
    }
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .task { await bootstrap() }
    .refreshable { await reload() }
  }

  @ViewBuilder private var content: some View {
    if let e = errorText {
      Text(e).foregroundColor(BoldTheme.Colors.textDim).padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoldTheme.Colors.bgPage)
    }
    else if isLoading && games.isEmpty {
      ProgressView("Loading…").tint(BoldTheme.Colors.gold).foregroundColor(BoldTheme.Colors.textDim)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoldTheme.Colors.bgPage)
    }
    else if games.isEmpty {
      Text("No picks yet.").foregroundColor(BoldTheme.Colors.textDim)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoldTheme.Colors.bgPage)
    }
    else {
      List(games) { g in
        GameRowView(
          game: g,
          logoFor: { id in id.flatMap { logoMap[$0] } },
          isSelected: true
        )
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(BoldTheme.Colors.bgPage)
    }
  }

  private func bootstrap() async {
    guard let client else { errorText = "No client"; return }
    isLoading = true; defer { isLoading = false }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext()
      season = ctx.season
      selectedWeek = ctx.week
      availableWeeks = try await GamesService(client: client).distinctWeeks(forSeason: season)

      // Fetch teams (inline; avoids dependency on TeamService)
      struct T: Decodable { let id: UUID; let logo_url: String? }
      let teamRes = try await client
        .from("teams")
        .select("id, logo_url")
        .execute()
      let teams = try JSONDecoder().decode([T].self, from: teamRes.data)
      logoMap = Dictionary(uniqueKeysWithValues: teams.map { t in (t.id, t.logo_url.flatMap { URL(string: $0) }) }).compactMapValues { $0 }

      try await reload()
    } catch { errorText = error.localizedDescription }
  }

  private func reload() async {
    guard let client else { return }
    isLoading = true; defer { isLoading = false }
    do {
      let userId = try await client.auth.session.user.id
      // Step 1: fetch game_ids for my picks this week
      struct GID: Decodable { let game_id: UUID }
      let pickRes = try await client
        .from("picks")
        .select("game_id")
        .eq("user_id", value: userId)
        .eq("season", value: season)
        .eq("week", value: selectedWeek)
        .execute()
      let ids = try JSONDecoder().decode([GID].self, from: pickRes.data).map { $0.game_id }
      guard !ids.isEmpty else { games = []; return }
      // Step 2: fetch those games
      let res = try await client
        .from("games")
        .select("""
          id, season, week, home_team, away_team, home_team_id, away_team_id, favorite_team_id, start_time, betting_line, latest_spread, picks_locked
        """)
        .in("id", values: ids)
        .order("start_time", ascending: true)
        .execute()
      let dec = JSONDecoder()
      dec.dateDecodingStrategy = .iso8601withFallback
      games = try dec.decode([Game].self, from: res.data)
    } catch { errorText = error.localizedDescription }
  }
}
