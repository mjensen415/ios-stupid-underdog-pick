import SwiftUI
import Supabase

@MainActor
final class PickemsViewModel: ObservableObject {
  @Published var season: Int?
  @Published var week: Int?
  @Published var availableWeeks: [Int] = []
  @Published var games: [PickemsGameRow] = []
  @Published var shortNames: [UUID: String] = [:]
  @Published var myPicks: [UUID: UUID] = [:]
  @Published var tiebreakerGuess: String = ""
  @Published var savedGuess: Int?
  @Published var isLoading = false
  @Published var pickingGameId: UUID?
  @Published var savingTiebreaker = false
  @Published var errorText: String?

  private var client: SupabaseClient?
  private var userId: UUID?

  func configure(client: SupabaseClient, userId: UUID?) {
    self.client = client
    self.userId = userId
  }

  func loadInitial() async {
    guard let client else { return }
    isLoading = true
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: "nfl")
      season = ctx.season
      week = ctx.week
      let svc = PickemsService(client: client)
      async let weeksTask = svc.fetchDistinctWeeks(season: ctx.season)
      async let namesTask = svc.fetchTeamShortNames()
      availableWeeks = try await weeksTask
      shortNames = try await namesTask
      await loadWeek()
    } catch {
      errorText = error.localizedDescription
      isLoading = false
    }
  }

  func loadWeek() async {
    guard let client, let season, let week else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let svc = PickemsService(client: client)
      games = try await svc.fetchGames(season: season, week: week)
      if let userId {
        myPicks = try await svc.fetchMyPicks(userId: userId, gameIds: games.map { $0.id })
        let guess = try await svc.fetchTiebreaker(userId: userId, season: season, week: week)
        savedGuess = guess
        tiebreakerGuess = guess.map { String($0) } ?? ""
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  var lastGame: PickemsGameRow? { games.max(by: { $0.startTime < $1.startTime }) }
  var tiebreakerLocked: Bool { (lastGame?.startTime ?? .distantFuture) <= Date() }

  var weekCorrect: Int {
    games.filter { g in
      guard let pick = myPicks[g.id], let winner = g.winnerTeamId else { return false }
      return pick == winner
    }.count
  }
  var weekPicked: Int { games.filter { myPicks[$0.id] != nil }.count }

  func pickTeam(_ game: PickemsGameRow, teamId: UUID) async {
    guard !game.isLocked, pickingGameId == nil, let client else { return }
    let prev = myPicks[game.id]
    myPicks[game.id] = teamId
    pickingGameId = game.id
    defer { pickingGameId = nil }
    do {
      try await PickemsService(client: client).submitPick(gameId: game.id, pickedTeamId: teamId)
    } catch {
      myPicks[game.id] = prev
      errorText = error.localizedDescription
    }
  }

  func saveTiebreaker() async {
    guard let client, let season, let week, !tiebreakerLocked else { return }
    guard let value = Int(tiebreakerGuess), value >= 0 else {
      errorText = "Enter a whole number for the tiebreaker guess."
      return
    }
    savingTiebreaker = true
    defer { savingTiebreaker = false }
    do {
      try await PickemsService(client: client).submitTiebreaker(season: season, week: week, guess: value)
      savedGuess = value
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private func dayLabel(_ date: Date) -> String {
  let f = DateFormatter()
  f.dateFormat = "EEEE, MMM d"
  return f.string(from: date).uppercased()
}

private func kickoffLabel(_ date: Date) -> String {
  let f = DateFormatter()
  f.dateFormat = "EEE h:mm a"
  return f.string(from: date)
}

struct PickemsView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject var appState: AppState
  @StateObject private var viewModel = PickemsViewModel()
  @State private var tab: Tab = .pick

  private enum Tab { case pick, standings }

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            header
            weekPills
            tabToggle

            if tab == .standings {
              PickemsStandingsView(season: viewModel.season, week: viewModel.week, lastGame: viewModel.lastGame)
            } else {
              tiebreakerCard
              gamesList
              footerSummary
            }
          }
          .padding(18)
        }
      }
      .navigationBarHidden(true)
      .task {
        if let client {
          viewModel.configure(client: client, userId: appState.session?.user.id)
          await viewModel.loadInitial()
        }
      }
      .onChange(of: viewModel.week) { _, _ in Task { await viewModel.loadWeek() } }
      .alert("Something went wrong", isPresented: Binding(
        get: { viewModel.errorText != nil },
        set: { if !$0 { viewModel.errorText = nil } }
      )) {
        Button("OK") { viewModel.errorText = nil }
      } message: {
        Text(viewModel.errorText ?? "")
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("NFL · \(viewModel.season.map { String($0) } ?? "")")
        .font(BoldTheme.Fonts.mono(10, weight: .semibold))
        .tracking(1.2)
        .foregroundColor(BoldTheme.Colors.green)
      Text("PRO BALL PICKEMS")
        .font(BoldTheme.Fonts.display(34))
        .foregroundColor(BoldTheme.Colors.text)
      Text("Pick the winner of every game. 1 point each.")
        .font(BoldTheme.Fonts.body(13))
        .foregroundColor(BoldTheme.Colors.textDim)
    }
  }

  private var weekPills: some View {
    Group {
      if viewModel.availableWeeks.count > 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(viewModel.availableWeeks, id: \.self) { w in
              let active = w == viewModel.week
              Button {
                viewModel.week = w
              } label: {
                Text("Week \(formatWeekLabel(w))")
                  .font(BoldTheme.Fonts.body(12.5, weight: .bold))
                  .padding(.horizontal, 16).padding(.vertical, 7)
                  .background(active ? BoldTheme.Colors.gold : BoldTheme.Colors.track)
                  .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
                  .clipShape(Capsule())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.top, 14)
      }
    }
  }

  private var tabToggle: some View {
    HStack(spacing: 6) {
      ForEach([Tab.pick, Tab.standings], id: \.self) { t in
        let active = tab == t
        Button {
          tab = t
        } label: {
          Text(t == .pick ? "Pick" : "Standings")
            .font(BoldTheme.Fonts.body(12.5, weight: .bold))
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(active ? BoldTheme.Colors.text : Color.clear)
            .foregroundColor(active ? BoldTheme.Colors.bgPage : BoldTheme.Colors.textDim)
            .overlay(Capsule().strokeBorder(active ? BoldTheme.Colors.text : BoldTheme.Colors.border, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.top, 14)
  }

  @ViewBuilder private var tiebreakerCard: some View {
    if let lastGame = viewModel.lastGame {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("TIEBREAKER")
            .font(BoldTheme.Fonts.body(11, weight: .bold))
            .foregroundColor(BoldTheme.Colors.goldDeep)
          Text(viewModel.tiebreakerLocked
            ? "Locked — \(lastGame.awayName ?? "") @ \(lastGame.homeName ?? "") already started"
            : "Combined score, \(lastGame.awayName ?? "") @ \(lastGame.homeName ?? "") (last game, \(kickoffLabel(lastGame.startTime)))")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        Spacer()
        TextField("--", text: $viewModel.tiebreakerGuess)
          .keyboardType(.numberPad)
          .multilineTextAlignment(.center)
          .font(BoldTheme.Fonts.display(20))
          .frame(width: 58, height: 34)
          .background(Color.white)
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .disabled(viewModel.tiebreakerLocked)
          .opacity(viewModel.tiebreakerLocked ? 0.5 : 1)
        if !viewModel.tiebreakerLocked {
          Button {
            Task { await viewModel.saveTiebreaker() }
          } label: {
            Text(viewModel.savedGuess != nil ? "Update" : "Save")
              .font(BoldTheme.Fonts.body(12, weight: .bold))
              .foregroundColor(.white)
              .padding(.horizontal, 12).padding(.vertical, 9)
              .background(BoldTheme.Colors.green)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .disabled(viewModel.savingTiebreaker || viewModel.tiebreakerGuess == (viewModel.savedGuess.map { String($0) } ?? ""))
        }
      }
      .padding(14)
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .padding(.top, 16)
    }
  }

  @ViewBuilder private var gamesList: some View {
    if viewModel.isLoading && viewModel.games.isEmpty {
      Text("Loading games…").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textFaint).frame(maxWidth: .infinity).padding(.vertical, 48)
    } else if viewModel.games.isEmpty {
      Text("No games scheduled this week.").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textFaint).frame(maxWidth: .infinity).padding(.vertical, 48)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(viewModel.games.enumerated()), id: \.element.id) { index, game in
          let prevDay = index > 0 ? dayLabel(viewModel.games[index - 1].startTime) : nil
          let day = dayLabel(game.startTime)
          if day != prevDay {
            Text(day)
              .font(BoldTheme.Fonts.mono(10))
              .tracking(0.9)
              .foregroundColor(BoldTheme.Colors.textFaint)
              .padding(.top, index == 0 ? 0 : 4)
          }
          PickemsGameRowView(
            game: game,
            myPick: viewModel.myPicks[game.id],
            homeColors: teamColors(viewModel.shortNames[game.homeTeamId]),
            awayColors: teamColors(viewModel.shortNames[game.awayTeamId])
          ) { teamId in
            Task { await viewModel.pickTeam(game, teamId: teamId) }
          }
        }
      }
      .padding(.top, 16)
    }
  }

  @ViewBuilder private var footerSummary: some View {
    if !viewModel.games.isEmpty {
      HStack {
        Text("Your week: \(viewModel.weekCorrect) correct, \(viewModel.weekPicked) picked")
          .font(BoldTheme.Fonts.body(11.5, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer()
      }
      .padding(14)
      .background(BoldTheme.Colors.track)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.top, 16)
    }
  }
}

private struct PickemsGameRowView: View {
  let game: PickemsGameRow
  let myPick: UUID?
  let homeColors: TeamColorPair
  let awayColors: TeamColorPair
  let onPick: (UUID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        if game.isLive {
          Circle().fill(Color(hex: 0xC6402A)).frame(width: 6, height: 6)
        }
        Text(game.isFinal ? "FINAL" : game.isLive ? "LIVE" : kickoffLabel(game.startTime))
          .font(BoldTheme.Fonts.mono(9.5, weight: .bold))
          .tracking(0.8)
          .foregroundColor(game.isLive ? Color(hex: 0xC6402A) : BoldTheme.Colors.textFaint)
      }
      HStack(spacing: 10) {
        teamButton(teamId: game.awayTeamId, name: game.awayName, logo: game.awayLogoUrl, colors: awayColors, points: game.awayPoints)
        teamButton(teamId: game.homeTeamId, name: game.homeName, logo: game.homeLogoUrl, colors: homeColors, points: game.homePoints)
      }
      if game.isFinal, let myPick {
        let correct = myPick == game.winnerTeamId
        Text(correct ? "You picked right · +1" : "You picked wrong")
          .font(BoldTheme.Fonts.body(10.5, weight: .bold))
          .foregroundColor(correct ? BoldTheme.Colors.green : Color(hex: 0xA6402A))
      }
    }
    .padding(14)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  @ViewBuilder
  private func teamButton(teamId: UUID, name: String?, logo: String?, colors: TeamColorPair, points: Int?) -> some View {
    let picked = myPick == teamId
    let isWinner = game.isFinal && game.winnerTeamId == teamId
    Button {
      onPick(teamId)
    } label: {
      HStack(spacing: 9) {
        TeamHelmet(logoUrl: logo, primaryColor: colors.primary, secondaryColor: colors.secondary, size: 30)
        Text((name ?? "").uppercased())
          .font(BoldTheme.Fonts.body(12.5, weight: picked ? .bold : .semibold))
          .foregroundColor(picked ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
          .lineLimit(1)
        Spacer(minLength: 0)
        if game.isLive || game.isFinal, let points {
          Text("\(points)")
            .font(BoldTheme.Fonts.display(17))
            .foregroundColor(isWinner ? BoldTheme.Colors.green : BoldTheme.Colors.text)
        } else if picked {
          Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(BoldTheme.Colors.green)
        }
      }
      .padding(.horizontal, 10).padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(picked ? BoldTheme.Colors.green : BoldTheme.Colors.border, lineWidth: picked ? 2 : 1.5)
      )
      .background(picked ? BoldTheme.Colors.green.opacity(0.08) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .opacity(game.isLocked && !picked ? 0.55 : 1)
    }
    .buttonStyle(.plain)
    .disabled(game.isLocked)
  }
}
