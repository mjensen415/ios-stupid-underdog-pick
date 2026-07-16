import SwiftUI
import Supabase

struct SeasonLeaderboardView: View {
  @EnvironmentObject var appState: AppState
  @State private var rows: [TotalsLeaderboardRow] = []
  @State private var names: [UUID: String] = [:]
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
      List {
      if !rows.isEmpty {
        LeaderboardHeaderRow()
      }
      ForEach(rows, id: \.id) { row in
        LeaderboardRow(
          rank: rows.firstIndex(where: { $0.id == row.id }).map { $0 + 1 } ?? 0,
          name: names[row.userId] ?? "Player",
          record: "\(row.wins ?? 0)W-\(row.losses ?? 0)L",
          points: String(format: "%.1f", row.totalPoints ?? 0)
        )
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .overlay(alignment: .top) {
      if let errorMessage {
        Text(errorMessage)
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(.red)
          .padding(.top)
      }
    }
    .overlay { if isLoading { ProgressView().tint(BoldTheme.Colors.gold) } }
    .refreshable { await load() }
    .task { await load() }
    .navigationTitle("Season")
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    guard let client = (try? await MainActor.run { appState.client }) else { return }
    do {
      // If you want current season only, pass context.season; else nil
      let ctx = try await ContextService(client: client).getCurrentContext()
      let list = try await LeaderboardService(client: client).fetchTotals(season: ctx.season)
      rows = list
      names = await fetchDisplayNames(client: client, userIds: list.map { $0.userId })
      errorMessage = nil
    } catch {
      errorMessage = "Can’t reach the server. Pull to retry."
    }
  }
}
