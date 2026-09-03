import SwiftUI
import Supabase

struct SeasonLeaderboardView: View {
  let sport: String
  let groupSlug: String?

  @EnvironmentObject var appState: AppState
  @State private var rows: [LeaderboardDisplayRow] = []
  @State private var availableSeasons: [Int] = []
  @State private var selectedSeason: Int?
  @State private var isLoading = false
  @State private var errorMessage: String?

  private var sportGroupKey: String { "\(sport)|\(groupSlug ?? "")" }

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
                    .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
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

      if rows.isEmpty {
        if !isLoading {
          Text("No season data available")
            .foregroundColor(BoldTheme.Colors.textDim)
            .listRowBackground(BoldTheme.Colors.bgPage)
            .listRowSeparator(.hidden)
        }
      } else {
        LeaderboardHeaderRow()
        ForEach(rows) { row in
          LeaderboardRow(
            rank: rows.firstIndex(where: { $0.id == row.id }).map { $0 + 1 } ?? 0,
            userId: row.userId,
            name: row.name,
            record: row.record,
            points: String(format: "%.1f", row.points),
            isLast: row.id == rows.last?.id
          )
        }
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
    .overlay { if isLoading && rows.isEmpty { ProgressView().tint(BoldTheme.Colors.gold) } }
    .refreshable { await loadSeason() }
    .task(id: sportGroupKey) { await loadInitial() }
  }

  private func loadInitial() async {
    isLoading = true
    defer { isLoading = false }
    guard let client = (await MainActor.run { appState.client }) else { return }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: sport)

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
    guard let client = (await MainActor.run { appState.client }) else { return }
    do {
      if let groupSlug {
        let result = try await GroupsService(client: client).fetchGroupLeaderboard(
          slug: groupSlug, scope: "season", season: season, week: nil, sport: sport
        )
        rows = result.leaderboard.map {
          LeaderboardDisplayRow(id: $0.user_id, userId: $0.user_id, name: $0.display_name ?? "Unknown", record: "\($0.wins)W-\($0.losses)L", points: $0.points)
        }
      } else {
        let list = try await LeaderboardService(client: client).fetchSeasonLeaderboard(season: season, sport: sport)
        rows = list.map {
          LeaderboardDisplayRow(id: $0.userId, userId: $0.userId, name: $0.displayName ?? "Unknown", record: "\($0.totalWins ?? 0)W-\($0.totalLosses ?? 0)L", points: $0.seasonPoints ?? 0)
        }
      }
      errorMessage = nil
    } catch {
      errorMessage = "Can't reach the server. Pull to retry."
    }
  }
}
