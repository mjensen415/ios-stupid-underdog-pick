import SwiftUI
import Supabase

@MainActor
final class WeeklyLeaderboardViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published var rows: [LeaderboardDisplayRow] = []
  @Published var availableWeeks: [Int] = []
  @Published var season: Int?
  @Published var week: Int?

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  // Full reload: re-derives season/current-week/available-weeks for the
  // given sport (a sport switch can change all three), then fetches rows.
  func loadInitial(sport: String, groupSlug: String?) async {
    guard let client else {
      errorText = "Client not available"
      return
    }
    isLoading = true; errorText = nil
    defer { isLoading = false }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: sport)
      let weeks = try await GamesService(client: client).distinctWeeks(forSeason: ctx.season, sport: sport)
      season = ctx.season
      availableWeeks = weeks
      week = weeks.contains(ctx.week) ? ctx.week : weeks.last
      await fetchRows(client: client, sport: sport, groupSlug: groupSlug)
    } catch {
      errorText = error.localizedDescription
      #if DEBUG
      print("[WeeklyLeaderboard][ERR]", error.localizedDescription)
      #endif
    }
  }

  // Rows-only reload -- used when just the week pill or the group/scope
  // selection changes, so season/available-weeks don't need re-deriving.
  func reloadRows(sport: String, groupSlug: String?) async {
    guard let client else { return }
    isLoading = true; errorText = nil
    defer { isLoading = false }
    await fetchRows(client: client, sport: sport, groupSlug: groupSlug)
  }

  private func fetchRows(client: SupabaseClient, sport: String, groupSlug: String?) async {
    guard let season, let week else { return }
    do {
      if let groupSlug {
        let result = try await GroupsService(client: client).fetchGroupLeaderboard(
          slug: groupSlug, scope: "week", season: season, week: week, sport: sport
        )
        rows = result.leaderboard.map {
          LeaderboardDisplayRow(id: $0.user_id, userId: $0.user_id, name: $0.display_name ?? "Unknown", record: "\($0.wins)W-\($0.losses)L", points: $0.points)
        }
      } else {
        let list = try await LeaderboardService(client: client).fetchWeek(season: season, week: week, sport: sport)
        let names = await fetchDisplayNames(client: client, userIds: list.map { $0.userId })
        rows = list.map {
          LeaderboardDisplayRow(id: $0.userId, userId: $0.userId, name: names[$0.userId] ?? "Player", record: "\($0.win ?? 0)W-\($0.loss ?? 0)L", points: $0.points ?? 0)
        }
      }
      #if DEBUG
      print("[WeeklyLeaderboard] count =", rows.count, "season =", season, "week =", week, "group =", groupSlug ?? "global")
      #endif
    } catch {
      errorText = error.localizedDescription
      #if DEBUG
      print("[WeeklyLeaderboard][ERR]", error.localizedDescription)
      #endif
    }
  }
}

struct WeeklyLeaderboardView: View {
  let sport: String
  let groupSlug: String?

  @Environment(\.supabaseClient) private var client
  @StateObject private var viewModel = WeeklyLeaderboardViewModel()

  private var sportGroupKey: String { "\(sport)|\(groupSlug ?? "")" }

  var body: some View {
    Group {
      if client == nil {
        Text("Client not available").foregroundColor(BoldTheme.Colors.textDim)
      } else if let e = viewModel.errorText {
        VStack(spacing: 8) {
          Text("Error loading leaderboard").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
          Text(e).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
          Button("Retry") { Task { await viewModel.loadInitial(sport: sport, groupSlug: groupSlug) } }
            .foregroundColor(BoldTheme.Colors.goldDeep)
        }.padding()
      } else if viewModel.isLoading && viewModel.rows.isEmpty {
        ProgressView("Loading leaderboard…").tint(BoldTheme.Colors.gold).foregroundColor(BoldTheme.Colors.textDim)
      } else {
        // Week pills stay visible even with zero rows for the selected
        // week, so an empty week is still a way to reach a non-empty one.
        List {
          if viewModel.availableWeeks.count > 1 {
            weekPills
          }
          if viewModel.rows.isEmpty {
            Text("No results yet for this week.")
              .foregroundColor(BoldTheme.Colors.textDim)
              .listRowBackground(BoldTheme.Colors.bgPage)
              .listRowSeparator(.hidden)
          } else {
            LeaderboardHeaderRow()
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
              LeaderboardRow(
                rank: index + 1,
                userId: row.userId,
                name: row.name,
                record: row.record,
                points: String(format: "%.1f", row.points),
                isLast: index == viewModel.rows.count - 1
              )
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BoldTheme.Colors.bgPage)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .task(id: sportGroupKey) {
      if let client {
        viewModel.configure(client: client)
        await viewModel.loadInitial(sport: sport, groupSlug: groupSlug)
      }
    }
    .refreshable {
      await viewModel.loadInitial(sport: sport, groupSlug: groupSlug)
    }
  }

  private var weekPills: some View {
    PillToggle(
      options: viewModel.availableWeeks.map { (label: "Week \(formatWeekLabel($0))", value: $0) },
      selection: Binding(
        get: { viewModel.week ?? viewModel.availableWeeks.last ?? 1 },
        set: { newWeek in
          viewModel.week = newWeek
          Task { await viewModel.reloadRows(sport: sport, groupSlug: groupSlug) }
        }
      ),
      scrollable: true
    )
    .listRowBackground(BoldTheme.Colors.bgPage)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
  }
}
