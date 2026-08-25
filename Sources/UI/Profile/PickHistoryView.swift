import SwiftUI

struct PickHistoryView: View {
  @Environment(\.supabaseClient) private var client

  @State private var picks: [Pick] = []
  @State private var gamesById: [UUID: Game] = [:]
  @State private var logoMap: [UUID: URL] = [:]
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var selectedSeason: Int?

  private var availableSeasons: [Int] {
    Array(Set(picks.map { $0.season })).sorted(by: >)
  }

  private var seasonPicks: [Pick] {
    picks.filter { $0.season == selectedSeason }
  }

  private var seasonSummary: (wins: Int, losses: Int, pending: Int) {
    seasonPicks.reduce((0, 0, 0)) { acc, pick in
      guard let game = gamesById[pick.game_id] else { return (acc.0, acc.1, acc.2 + 1) }
      switch game.outcome(forPickedTeamId: pick.picked_team_id) {
      case .win: return (acc.0 + 1, acc.1, acc.2)
      case .loss: return (acc.0, acc.1 + 1, acc.2)
      case .pending: return (acc.0, acc.1, acc.2 + 1)
      }
    }
  }

  // CFB and Pro Ball run on offset week numbering (see formatWeekLabel),
  // so grouping by raw week alone can silently interleave a CFB pick and
  // an NFL pick from different weeks under one ambiguous "WEEK 3" header.
  // Sport comes from the joined game, not Pick itself (picks don't carry
  // sport directly).
  private struct WeekGroupKey: Hashable { let sport: String; let week: Int }

  private func sport(for pick: Pick) -> String {
    gamesById[pick.game_id]?.sport ?? "cfb"
  }

  private var picksByWeek: [WeekGroupKey: [Pick]] {
    Dictionary(grouping: seasonPicks, by: { WeekGroupKey(sport: sport(for: $0), week: $0.week) })
  }

  var body: some View {
    Group {
      if let errorText {
        VStack(spacing: 8) {
          Text("Error loading history").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
          Text(errorText).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
          Button("Retry") { Task { await load() } }
            .foregroundColor(BoldTheme.Colors.goldDeep)
        }.padding()
      } else if isLoading && picks.isEmpty {
        ProgressView("Loading…").tint(BoldTheme.Colors.gold).foregroundColor(BoldTheme.Colors.textDim)
      } else if picks.isEmpty {
        Text("No pick history yet.").foregroundColor(BoldTheme.Colors.textDim)
      } else {
        List {
          if availableSeasons.count > 1 {
            Section {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                  ForEach(availableSeasons, id: \.self) { season in
                    let active = season == selectedSeason
                    Button {
                      selectedSeason = season
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

          Section {
            HStack {
              Text(verbatim: "\(selectedSeason ?? 0) Summary")
                .font(BoldTheme.Fonts.mono(11))
                .foregroundColor(BoldTheme.Colors.textFaint)
              Spacer()
              Text(verbatim: "\(seasonSummary.wins)W-\(seasonSummary.losses)L")
                .font(BoldTheme.Fonts.display(20))
                .foregroundColor(BoldTheme.Colors.text)
              if seasonSummary.pending > 0 {
                Text(verbatim: "· \(seasonSummary.pending) pending")
                  .font(BoldTheme.Fonts.body(12))
                  .foregroundColor(BoldTheme.Colors.textFaint)
              }
            }
            .padding(.vertical, 4)
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
          .listRowSeparator(.hidden)

          ForEach(
            picksByWeek.keys.sorted(by: { $0.week != $1.week ? $0.week > $1.week : $0.sport < $1.sport }),
            id: \.self
          ) { key in
            Section {
              ForEach(picksByWeek[key] ?? []) { pick in
                if let game = gamesById[pick.game_id] {
                  GameRowView(
                    game: game,
                    logoFor: { id in id.flatMap { logoMap[$0] } },
                    isSelected: true
                  )
                }
              }
            } header: {
              Text(verbatim: "\(key.sport == "nfl" ? "PRO BALL" : "CFB") · WEEK \(formatWeekLabel(key.week))")
                .font(BoldTheme.Fonts.mono(11))
                .tracking(0.9)
                .foregroundColor(BoldTheme.Colors.textFaint)
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BoldTheme.Colors.bgPage)
      }
    }
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .navigationTitle("Pick History")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(BoldTheme.Colors.bgPage, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    // Frost's bgPage is light now (was dark under Bold) -- see
    // LeaderboardView.swift for the same fix and rationale.
    .toolbarColorScheme(.light, for: .navigationBar)
    .task { await load() }
  }

  private func load() async {
    guard let client else { errorText = "No client"; return }
    isLoading = true
    errorText = nil
    defer { isLoading = false }
    do {
      let allPicks = try await PicksService(client: client).myPicks()
      let gameIds = Array(Set(allPicks.map { $0.game_id }))
      guard !gameIds.isEmpty else {
        picks = []
        return
      }

      // v_games_named, not the raw games table -- see Game.CodingKeys for why.
      let res = try await client
        .from("v_games_named")
        .select("""
          id, season, week, status, home_name, away_name, home_team_id, away_team_id, favorite_team_id, start_time, betting_line, latest_spread, picks_locked, home_points, away_points, sport
        """)
        .in("id", values: gameIds)
        .execute()
      let dec = JSONDecoder()
      dec.dateDecodingStrategy = .iso8601withFallback
      let games = try dec.decode([Game].self, from: res.data)

      struct T: Decodable { let id: UUID; let logo_url: String? }
      let teamRes = try await client.from("teams").select("id, logo_url").execute()
      let teams = try JSONDecoder().decode([T].self, from: teamRes.data)

      await MainActor.run {
        gamesById = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
        logoMap = Dictionary(uniqueKeysWithValues: teams.map { t in (t.id, t.logo_url.flatMap { URL(string: $0) }) }).compactMapValues { $0 }
        picks = allPicks
        if selectedSeason == nil {
          selectedSeason = allPicks.map { $0.season }.max()
        }
      }
    } catch {
      await MainActor.run { errorText = error.localizedDescription }
    }
  }
}
