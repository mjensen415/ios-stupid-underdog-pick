import SwiftUI
import Supabase

@MainActor
final class WeeklyLeaderboardViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published var rows: [WeeklyLeaderboardRow] = []

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
        Text("Client not available").foregroundStyle(.secondary)
      } else if let e = viewModel.errorText {
        VStack(spacing: 8) {
          Text("Error loading leaderboard").font(.title3.bold())
          Text(e).foregroundStyle(.secondary).multilineTextAlignment(.center)
          Button("Retry") { Task { await viewModel.load() } }
        }.padding()
      } else if viewModel.isLoading {
        ProgressView("Loading leaderboard…")
      } else if viewModel.rows.isEmpty {
        Text("No results yet for this week.").foregroundStyle(.secondary)
      } else {
        List(viewModel.rows) { row in
          HStack {
            VStack(alignment: .leading) {
              Text("User \(row.userId.uuidString.prefix(8))…").font(.headline)
              Text("W \(row.win ?? 0) • L \(row.loss ?? 0)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1f", row.points ?? 0))
              .font(.headline)
          }
        }
      }
    }
    .task {
      if let client {
        viewModel.configure(client: client)
        await viewModel.load()
      }
    }
    .refreshable {
      await viewModel.load()
    }
    .navigationTitle("Weekly Leaderboard")
  }
}
