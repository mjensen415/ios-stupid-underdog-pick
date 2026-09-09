import SwiftUI
import Supabase

// My Picks previously only ever showed Underdog Pick history, with no way
// to see -- at a glance, per contest -- what you picked THIS week and no
// path back to change it. Mirrors web's ThisWeekPicks.tsx: same
// CFB/Pro Ball/Pickems switcher already used on Groups/Leaderboard, only
// shows contests the user is actually in a group for.
@MainActor
final class ThisWeekPicksViewModel: ObservableObject {
  @Published var eligible: (cfb: Bool, nfl: Bool, pickems: Bool)?
  @Published var underdogWeek: Int?
  @Published var underdogPick: (pickedTeam: String, oppTeam: String, spread: Double?)?
  @Published var underdogHasNoPick = false
  @Published var pickemsWeek: Int?
  @Published var pickemsTotal = 0
  @Published var pickemsPicked = 0

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  func loadEligibility() async {
    guard let client else { return }
    do {
      let groups = try await GroupsService(client: client).fetchMyGroups()
      eligible = (
        cfb: groups.contains { $0.game_type != .pickems && ($0.sport == .cfb || $0.sport == .both) },
        nfl: groups.contains { $0.game_type != .pickems && ($0.sport == .nfl || $0.sport == .both) },
        pickems: groups.contains { $0.game_type == .pickems || $0.game_type == .both }
      )
    } catch {
      eligible = (false, false, false)
    }
  }

  func loadUnderdog(sport: String) async {
    guard let client else { return }
    underdogPick = nil
    underdogHasNoPick = false
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: sport)
      underdogWeek = ctx.week
      guard let pick = try await PicksService(client: client).myPick(season: ctx.season, week: ctx.week, sport: sport) else {
        underdogHasNoPick = true
        return
      }
      let games = try await GamesService(client: client).fetch(season: ctx.season, week: ctx.week, sport: sport)
      guard let game = games.first(where: { $0.id == pick.game_id }) else {
        underdogHasNoPick = true
        return
      }
      let pickedIsHome = pick.picked_team_id == game.homeTeamId
      let pickedTeam = pickedIsHome ? (game.homeTeam ?? "Home") : (game.awayTeam ?? "Away")
      let oppTeam = pickedIsHome ? (game.awayTeam ?? "Away") : (game.homeTeam ?? "Home")
      underdogPick = (pickedTeam, oppTeam, game.latestSpread)
    } catch {
      underdogHasNoPick = true
    }
  }

  func loadPickems() async {
    guard let client else { return }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: "nfl")
      pickemsWeek = ctx.week
      let service = PickemsService(client: client)
      let games = try await service.fetchGames(season: ctx.season, week: ctx.week, sport: "nfl")
      pickemsTotal = games.count
      let userId = try await client.auth.session.user.id
      let picks = try await service.fetchMyPicks(userId: userId, gameIds: games.map { $0.id })
      pickemsPicked = picks.count
    } catch {
      pickemsTotal = 0
      pickemsPicked = 0
    }
  }
}

struct ThisWeekPicksView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject private var appState: AppState
  @StateObject private var viewModel = ThisWeekPicksViewModel()

  var body: some View {
    Group {
      if let eligible = viewModel.eligible {
        let options: [(label: String, value: CurrentGame)] = [
          eligible.cfb ? ("CFB", .cfb) : nil,
          eligible.nfl ? ("PRO BALL", .nfl) : nil,
          eligible.pickems ? ("PICKEMS", .pickems) : nil,
        ].compactMap { $0 }

        if !options.isEmpty {
          let activeGame = options.contains(where: { $0.value == appState.currentGame }) ? appState.currentGame : options[0].value

          VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK").font(BoldTheme.Fonts.display(20)).tracking(0.6).foregroundColor(BoldTheme.Colors.text)

            if options.count > 1 {
              PillToggle(
                options: options,
                selection: Binding(get: { activeGame }, set: { appState.currentGame = $0 }),
                scrollable: true
              )
            }

            content(for: activeGame)
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
          .task(id: activeGame) { await load(for: activeGame) }
        }
      }
    }
    .task {
      if let client {
        viewModel.configure(client: client)
        await viewModel.loadEligibility()
      }
    }
  }

  @ViewBuilder
  private func content(for game: CurrentGame) -> some View {
    switch game {
    case .cfb, .nfl:
      underdogCard(sport: game == .nfl ? "nfl" : "cfb")
    case .pickems:
      pickemsCard
    }
  }

  private func underdogCard(sport: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(sport == "nfl" ? "Pro Ball" : "CFB") · Week \(formatWeekLabel(viewModel.underdogWeek ?? 0))")
          .font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
        if let pick = viewModel.underdogPick {
          Text(pick.pickedTeam).font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
          Text("vs \(pick.oppTeam)" + (pick.spread.map { " · Line \($0 > 0 ? "+" : "")\($0)" } ?? ""))
            .font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
        } else {
          Text("No pick yet this week.").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.text)
        }
      }
      Spacer()
      Button {
        appState.goToUnderdog(sport: sport)
      } label: {
        Text(viewModel.underdogPick != nil ? "Change pick →" : "Make a pick →")
          .font(BoldTheme.Fonts.body(13, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.goldDeep)
      }
    }
    .padding(14)
    .background(BoldTheme.Colors.text.opacity(0.04))
    .cornerRadius(14)
  }

  private var pickemsCard: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("Pickems · Week \(formatWeekLabel(viewModel.pickemsWeek ?? 0))")
          .font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
        if viewModel.pickemsTotal == 0 {
          Text("No games yet.").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.text)
        } else {
          Text("\(viewModel.pickemsPicked) of \(viewModel.pickemsTotal) games picked")
            .font(BoldTheme.Fonts.body(15, weight: .semibold))
            .foregroundColor(viewModel.pickemsPicked == viewModel.pickemsTotal ? BoldTheme.Colors.green : BoldTheme.Colors.text)
        }
      }
      Spacer()
      Button {
        appState.goToPickems()
      } label: {
        Text(viewModel.pickemsPicked > 0 ? "Change picks →" : "Make picks →")
          .font(BoldTheme.Fonts.body(13, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.goldDeep)
      }
    }
    .padding(14)
    .background(BoldTheme.Colors.text.opacity(0.04))
    .cornerRadius(14)
  }

  private func load(for game: CurrentGame) async {
    switch game {
    case .cfb: await viewModel.loadUnderdog(sport: "cfb")
    case .nfl: await viewModel.loadUnderdog(sport: "nfl")
    case .pickems: await viewModel.loadPickems()
    }
  }
}
