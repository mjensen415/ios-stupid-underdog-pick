import SwiftUI
import Supabase

@MainActor
final class LeaderboardScopeViewModel: ObservableObject {
  @Published var boardScope: LeaderboardBoardScope = .global
  @Published var myGroups: [MyGroup] = []
  @Published var selectedGroupSlug: String?

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  // Silent on failure -- Global scope (the default) works fine with no
  // groups loaded, so a groups-mine hiccup shouldn't block the screen.
  func loadGroups() async {
    guard let client else { return }
    do {
      let groups = try await GroupsService(client: client).fetchMyGroups()
      myGroups = groups
      if selectedGroupSlug == nil { selectedGroupSlug = groups.first?.slug }
    } catch {
      #if DEBUG
      print("[LeaderboardScope][ERR]", error.localizedDescription)
      #endif
    }
  }
}

struct LeaderboardView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject private var appState: AppState
  @StateObject private var scopeVM = LeaderboardScopeViewModel()
  @State private var selection: Int = 0 // 0 weekly, 1 season
  @State private var pickemsSeason: Int?
  @State private var pickemsWeek: Int?
  @State private var pickemsLastGame: PickemsGameRow?

  // nil = global board; a slug scopes both sub-screens to that group's own
  // members-only standings, matching web's boardScope/selectedGroupSlug.
  private var activeGroupSlug: String? {
    scopeVM.boardScope == .group ? scopeVM.selectedGroupSlug : nil
  }

  // Only groups that actually play the currently-viewed underdog sport --
  // picking a Pickems-only (or wrong-sport) group here would just show an
  // empty board via the group-scoped fetch. Mirrors web's Leaderboard.tsx.
  private var underdogGroups: [MyGroup] {
    scopeVM.myGroups.filter { $0.game_type != .pickems && ($0.sport.rawValue == appState.currentGame.rawValue || $0.sport == .both) }
  }

  private func loadPickemsContext() async {
    guard let client else { return }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: "nfl")
      pickemsSeason = ctx.season
      pickemsWeek = ctx.week
      let games = try await PickemsService(client: client).fetchGames(season: ctx.season, week: ctx.week)
      pickemsLastGame = games.max(by: { $0.startTime < $1.startTime })
    } catch {
      // Tiebreaker line just won't show -- non-fatal, standings still load.
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        // CFB Underdog, Pro Ball Underdog, and Pickems are separate
        // contests with separate groups (Pickems also has a completely
        // different scoring mechanic) -- this replaces the CFB/Pro Ball-
        // only toggle, which had no way to reach Pickems standings at all.
        // appState.currentGame is shared with Home/Games/Groups so the
        // choice stays consistent across the app.
        PillToggle(
          options: [
            (label: "CFB", value: CurrentGame.cfb),
            (label: "PRO BALL", value: .nfl),
            (label: "PICKEMS", value: .pickems),
          ],
          selection: $appState.currentGame
        )
        .padding(.horizontal)
        .padding(.top, 8)

        if appState.currentGame == .pickems {
          PickemsStandingsView(season: pickemsSeason, week: pickemsWeek, lastGame: pickemsLastGame)
            .task { await loadPickemsContext() }
        } else {
          if !underdogGroups.isEmpty {
            PillToggle(
              options: [(label: "Global", value: LeaderboardBoardScope.global), (label: "Group", value: .group)],
              selection: $scopeVM.boardScope
            )
            .padding(.horizontal)

            if scopeVM.boardScope == .group && underdogGroups.count > 1 {
              PillToggle(
                options: underdogGroups.map { (label: $0.name, value: $0.slug) },
                selection: Binding(
                  get: { scopeVM.selectedGroupSlug ?? underdogGroups[0].slug },
                  set: { scopeVM.selectedGroupSlug = $0 }
                ),
                scrollable: true
              )
              .padding(.horizontal)
            }
          }

          Picker("Mode", selection: $selection) {
            Text("Weekly").tag(0)
            Text("Season").tag(1)
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)

          if selection == 0 {
            WeeklyLeaderboardView(sport: appState.currentGame.rawValue, groupSlug: activeGroupSlug)
          } else {
            SeasonLeaderboardView(sport: appState.currentGame.rawValue, groupSlug: activeGroupSlug)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
      .navigationTitle(selection == 0 ? "Weekly Leaderboard" : "Season")
      .toolbarBackground(BoldTheme.Colors.bgPage, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      // Frost's bgPage is light now (was dark under Bold), so nav bar
      // chrome (title/buttons) needs the light color scheme for contrast --
      // .dark would render light-on-light and be illegible.
      .toolbarColorScheme(.light, for: .navigationBar)
      .task {
        if let client {
          scopeVM.configure(client: client)
          await scopeVM.loadGroups()
        }
      }
      // Keep the selected group valid when switching contests -- otherwise
      // a stale slug from the other sport silently returns no data.
      .onChange(of: appState.currentGame) { _, newGame in
        guard newGame != .pickems, !underdogGroups.isEmpty else { return }
        if !underdogGroups.contains(where: { $0.slug == scopeVM.selectedGroupSlug }) {
          scopeVM.selectedGroupSlug = underdogGroups[0].slug
        }
      }
    }
    .tint(BoldTheme.Colors.gold)
  }
}
