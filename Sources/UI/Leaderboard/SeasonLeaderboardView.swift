import SwiftUI
import Supabase

struct SeasonLeaderboardView: View {
  @EnvironmentObject var appState: AppState
  @State private var rows: [SeasonLeaderboardRow] = []
  @State private var availableSeasons: [Int] = []
  @State private var selectedSeason: Int?
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    List {
      if availableSeasons.count > 1 {
        Section {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(availableSeasons, id: \.self) { season in
                let active = season == selectedSeason
                Button {
                  guard season != selectedSeason else { return }
                  selectedSeason = season
                  Task { await loadSeason() }
                } label: {
                  Text(verbatim: "\(season)")
                    .font(BoldTheme.Fonts.body(13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(active ? BoldTheme.Colors.gold : BoldTheme.Colors.text.opacity(0.07))
                    .foregroundColor(active ? BoldTheme.Colors.bgPage : BoldTheme.Colors.textDim)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .listRowBackground(BoldTheme.Colors.bgPage)
        .listRowSeparator(.hidden)
      }

      if !rows.isEmpty {
        LeaderboardHeaderRow()
      }
      ForEach(rows) { row in
        LeaderboardRow(
          rank: rows.firstIndex(where: { $0.id == row.id }).map { $0 + 1 } ?? 0,
          name: row.displayName ?? "Player",
          record: "\(row.totalWins ?? 0)W-\(row.totalLosses ?? 0)L",
          points: String(format: "%.1f", row.seasonPoints ?? 0)
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
    .refreshable { await loadSeason() }
    .task { await loadInitial() }
  }

  private func loadInitial() async {
    isLoading = true
    defer { isLoading = false }
    guard let client = (try? await MainActor.run { appState.client }) else { return }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext()

      struct SeasonRow: Decodable { let season: Int }
      let res = try await client
        .from("games")
        .select("season")
        .order("season", ascending: false)
        .execute()
      let seasons = try JSONDecoder().decode([SeasonRow].self, from: res.data)
      let distinctSeasons = Array(Set(seasons.map { $0.season })).sorted(by: >)

      await MainActor.run {
        availableSeasons = distinctSeasons
        selectedSeason = ctx.season
      }
      await loadSeason()
    } catch {
      errorMessage = "Can't reach the server. Pull to retry."
    }
  }

  private func loadSeason() async {
    guard let season = selectedSeason else { return }
    isLoading = true
    defer { isLoading = false }
    guard let client = (try? await MainActor.run { appState.client }) else { return }
    do {
      let list = try await LeaderboardService(client: client).fetchSeasonLeaderboard(season: season)
      rows = list
      errorMessage = nil
    } catch {
      errorMessage = "Can't reach the server. Pull to retry."
    }
  }
}
