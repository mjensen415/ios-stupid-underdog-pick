import SwiftUI
import Supabase

struct SeasonLeaderboardView: View {
  @EnvironmentObject var appState: AppState
  @State private var rows: [TotalsLeaderboardRow] = []
  @State private var names: [UUID: String] = [:]
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
      List(rows, id: \.id) { row in
      HStack {
        Text("\(rows.firstIndex(where: { $0.id == row.id }).map { $0 + 1 } ?? 0)").monospacedDigit()
        Text(names[row.userId] ?? "Player")
        Spacer()
        Text("\(row.wins ?? 0)-\(row.losses ?? 0)-\(row.pending ?? 0)")
        Text("\(row.totalPoints ?? 0, specifier: "%.1f") pts").frame(minWidth: 72, alignment: .trailing)
      }
    }
    .overlay(alignment: .top) {
      if let errorMessage {
        Text(errorMessage)
          .foregroundColor(.red)
          .padding(.top)
      }
    }
    .overlay { if isLoading { ProgressView() } }
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
