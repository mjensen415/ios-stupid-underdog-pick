import SwiftUI
import Supabase

@MainActor
final class WeeklyLeaderboardViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published var rows: [WeeklyLeaderboardRow] = []
  @Published var names: [UUID: String] = [:]

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  func load() async {
    guard let client else {
      errorText = "Client not available"
      return
    }
    isLoading = true; errorText = nil
    defer { isLoading = false }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext()
      let list = try await LeaderboardService(client: client).fetchWeek(season: ctx.season, week: ctx.week)
      rows = list
      names = await fetchDisplayNames(client: client, userIds: list.map { $0.userId })
      #if DEBUG
      print("[WeeklyLeaderboard] count =", list.count, "season =", ctx.season, "week =", ctx.week)
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
  @Environment(\.supabaseClient) private var client
  @StateObject private var viewModel = WeeklyLeaderboardViewModel()

  var body: some View {
    Group {
      if client == nil {
        Text("Client not available").foregroundColor(BoldTheme.Colors.textDim)
      } else if let e = viewModel.errorText {
        VStack(spacing: 8) {
          Text("Error loading leaderboard").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
          Text(e).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
          Button("Retry") { Task { await viewModel.load() } }
            .foregroundColor(BoldTheme.Colors.goldDeep)
        }.padding()
      } else if viewModel.isLoading {
        ProgressView("Loading leaderboard…").tint(BoldTheme.Colors.gold).foregroundColor(BoldTheme.Colors.textDim)
      } else if viewModel.rows.isEmpty {
        Text("No results yet for this week.").foregroundColor(BoldTheme.Colors.textDim)
      } else {
        List {
          LeaderboardHeaderRow()
          ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
            LeaderboardRow(
              rank: index + 1,
              name: viewModel.names[row.userId] ?? "Player",
              record: "\(row.win ?? 0)W-\(row.loss ?? 0)L",
              points: String(format: "%.1f", row.points ?? 0),
              isLast: index == viewModel.rows.count - 1
            )
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BoldTheme.Colors.bgPage)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .task {
      if let client {
        viewModel.configure(client: client)
        await viewModel.load()
      }
    }
    .refreshable {
      await viewModel.load()
    }
  }
}
