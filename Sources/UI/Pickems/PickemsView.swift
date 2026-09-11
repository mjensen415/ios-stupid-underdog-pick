import SwiftUI
import Supabase

@MainActor
final class PickemsViewModel: ObservableObject {
  @Published var season: Int?
  @Published var week: Int?
  @Published var availableWeeks: [Int] = []
  @Published var games: [PickemsGameRow] = []
  @Published var myPicks: [UUID: UUID] = [:]
  @Published var tiebreakerGuess: String = ""
  @Published var savedGuess: Int?
  @Published var isLoading = false
  @Published var pickingGameId: UUID?
  @Published var savingTiebreaker = false
  @Published var errorText: String?
  @Published var managedProfiles: [ManagedProfile] = []
  @Published var actingAs: ManagedProfile?
  @Published var savingChild = false
  @Published var myStanding: (correct: Int, total: Int, rank: Int)?
  @Published var pickPcts: [UUID: [UUID: (count: Int, total: Int)]] = [:]

  private var client: SupabaseClient?
  private var userId: UUID?

  func configure(client: SupabaseClient, userId: UUID?) {
    self.client = client
    self.userId = userId
  }

  func loadManagedProfiles() async {
    guard let client else { return }
    do {
      managedProfiles = try await PickemsService(client: client).fetchManagedProfiles()
    } catch {
      errorText = error.localizedDescription
    }
  }

  func addManagedProfile(name: String) async {
    guard let client, let userId, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    savingChild = true
    defer { savingChild = false }
    do {
      try await PickemsService(client: client).addManagedProfile(ownerUserId: userId, displayName: name.trimmingCharacters(in: .whitespaces))
      await loadManagedProfiles()
    } catch {
      errorText = error.localizedDescription
    }
  }

  func removeManagedProfile(_ profile: ManagedProfile) async {
    guard let client else { return }
    do {
      try await PickemsService(client: client).removeManagedProfile(id: profile.id)
      if actingAs?.id == profile.id { actingAs = nil }
      await loadManagedProfiles()
    } catch {
      errorText = error.localizedDescription
    }
  }

  func loadInitial() async {
    guard let client else { return }
    isLoading = true
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: "nfl")
      season = ctx.season
      week = ctx.week
      let svc = PickemsService(client: client)
      availableWeeks = try await svc.fetchDistinctWeeks(season: ctx.season)
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
        myPicks = try await svc.fetchMyPicks(userId: userId, gameIds: games.map { $0.id }, actingAsProfileId: actingAs?.id)
        let guess = try await svc.fetchTiebreaker(userId: userId, season: season, week: week, actingAsProfileId: actingAs?.id)
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
      try await PickemsService(client: client).submitPick(gameId: game.id, pickedTeamId: teamId, actingAsProfileId: actingAs?.id)
    } catch {
      myPicks[game.id] = prev
      errorText = error.localizedDescription
    }
  }

  // At-a-glance record/rank/pts for the header strip.
  func loadStanding(groupId: UUID) async {
    guard let client, let season, let week, let userId else { myStanding = nil; return }
    do {
      let rows = try await PickemsService(client: client).fetchGroupLeaderboard(groupId: groupId, season: season, sport: "nfl", week: week)
      let ranked = rankRows(rows, scope: .week, actualTotal: nil)
      let mineId = actingAs?.id ?? userId
      if let mine = ranked.first(where: { $0.row.userId == mineId }) {
        myStanding = (mine.row.weekCorrect, mine.row.weekTotalPicks, mine.rank)
      } else {
        myStanding = nil
      }
    } catch {
      myStanding = nil
    }
  }

  // Group-scoped "% picked" per team, per game.
  func loadPickPcts(groupId: UUID) async {
    guard let client, let season, let week else { pickPcts = [:]; return }
    do {
      let rows = try await PickemsService(client: client).fetchGroupPickPcts(groupId: groupId, season: season, week: week)
      var byGame: [UUID: [UUID: (count: Int, total: Int)]] = [:]
      for r in rows {
        byGame[r.gameId, default: [:]][r.pickedTeamId] = (r.pickCount, r.totalPicks)
      }
      pickPcts = byGame
    } catch {
      pickPcts = [:]
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
      try await PickemsService(client: client).submitTiebreaker(season: season, week: week, guess: value, actingAsProfileId: actingAs?.id)
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
  @State private var myGroups: [MyGroup]?
  @State private var showActorPicker = false
  @State private var showManageProfiles = false
  @State private var newChildName = ""

  private enum Tab { case pick, standings }

  private var hasEligibleGroup: Bool {
    (myGroups ?? []).contains { $0.game_type == .pickems || $0.game_type == .both }
  }

  // First Pickems-eligible group, for the at-a-glance strip and "% picked"
  // -- same "first group" default PickemsStandingsView uses without a
  // fixedGroupId. A user in several Pickems groups only sees one group's
  // numbers here; the Standings tab is where they compare.
  private var pickemsGroupId: UUID? {
    (myGroups ?? []).first { $0.game_type == .pickems || $0.game_type == .both }?.group_id
  }

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()
        if myGroups == nil {
          Color.clear
        } else if !hasEligibleGroup {
          PickemsWelcomeView { await loadMyGroups() }
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              header
              if tab == .pick { atAGlanceStrip }
              if tab == .pick { actorPicker }
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
      }
      .navigationBarHidden(true)
      .task {
        await loadMyGroups()
        if let client {
          viewModel.configure(client: client, userId: appState.session?.user.id)
          await viewModel.loadInitial()
          await viewModel.loadManagedProfiles()
        }
      }
      .onChange(of: viewModel.week) { _, _ in Task { await viewModel.loadWeek() } }
      .onChange(of: viewModel.actingAs) { _, _ in Task { await viewModel.loadWeek() } }
      .task(id: "\(pickemsGroupId?.uuidString ?? "")|\(viewModel.season ?? 0)|\(viewModel.week ?? 0)") {
        if let pickemsGroupId {
          await viewModel.loadStanding(groupId: pickemsGroupId)
          await viewModel.loadPickPcts(groupId: pickemsGroupId)
        }
      }
      .alert("Something went wrong", isPresented: Binding(
        get: { viewModel.errorText != nil },
        set: { if !$0 { viewModel.errorText = nil } }
      )) {
        Button("OK") { viewModel.errorText = nil }
      } message: {
        Text(viewModel.errorText ?? "")
      }
      .confirmationDialog("Picking as", isPresented: $showActorPicker, titleVisibility: .visible) {
        Button("You") { viewModel.actingAs = nil }
        ForEach(viewModel.managedProfiles) { profile in
          Button(profile.displayName) { viewModel.actingAs = profile }
        }
        Button("Manage Profiles…") { showManageProfiles = true }
        Button("Cancel", role: .cancel) {}
      }
      .sheet(isPresented: $showManageProfiles) {
        manageProfilesSheet
      }
    }
  }

  @ViewBuilder private var atAGlanceStrip: some View {
    if let standing = viewModel.myStanding {
      HStack(spacing: 0) {
        atAGlanceCell(
          value: "\(standing.correct)-\(max(standing.total - standing.correct, 0))",
          label: "RECORD", color: BoldTheme.Colors.text, showDivider: true
        )
        atAGlanceCell(value: "#\(standing.rank)", label: "RANK", color: BoldTheme.Colors.goldDeep, showDivider: true)
        atAGlanceCell(value: "\(standing.correct)", label: "PTS", color: BoldTheme.Colors.green, showDivider: false)
      }
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .padding(.top, 12)
    }
  }

  private func atAGlanceCell(value: String, label: String, color: Color, showDivider: Bool) -> some View {
    VStack(spacing: 2) {
      Text(value).font(BoldTheme.Fonts.display(24)).foregroundColor(color)
      Text(label).font(BoldTheme.Fonts.mono(9.5)).tracking(0.9).foregroundColor(BoldTheme.Colors.textFaint)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .overlay(alignment: .trailing) {
      if showDivider { Rectangle().fill(BoldTheme.Colors.border).frame(width: 1) }
    }
  }

  private var actorPicker: some View {
    Button {
      showActorPicker = true
    } label: {
      HStack(spacing: 6) {
        Text("Picking as")
          .font(BoldTheme.Fonts.body(11, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.textFaint)
        Text(viewModel.actingAs?.displayName ?? "You")
          .font(BoldTheme.Fonts.body(12.5, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(BoldTheme.Colors.textFaint)
      }
      .padding(.horizontal, 12).padding(.vertical, 7)
      .background(BoldTheme.Colors.track)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .padding(.top, 14)
  }

  private var manageProfilesSheet: some View {
    NavigationStack {
      List {
        Section {
          ForEach(viewModel.managedProfiles) { profile in
            HStack {
              Text(profile.displayName).font(BoldTheme.Fonts.body(14, weight: .semibold))
              Spacer()
              Button("Remove") {
                Task { await viewModel.removeManagedProfile(profile) }
              }
              .font(BoldTheme.Fonts.body(12, weight: .bold))
              .foregroundColor(Color(hex: 0xA6402A))
            }
          }
        } header: {
          Text("Child Profiles")
        } footer: {
          Text("Add a child profile to pick on their behalf. They'll show up as their own entry in your groups' standings.")
        }
        Section {
          HStack {
            TextField("Child's name", text: $newChildName)
            Button {
              Task {
                await viewModel.addManagedProfile(name: newChildName)
                newChildName = ""
              }
            } label: {
              Text("Add").font(BoldTheme.Fonts.body(13, weight: .bold))
            }
            .disabled(viewModel.savingChild || newChildName.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
      }
      .navigationTitle("Manage Profiles")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { showManageProfiles = false }
        }
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
                Text("Week \(w)")
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
            pickPcts: viewModel.pickPcts[game.id] ?? [:]
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

  private func loadMyGroups() async {
    guard let client else { return }
    do {
      myGroups = try await GroupsService(client: client).fetchMyGroups()
    } catch {
      myGroups = []
    }
  }
}

private struct PickemsGameRowView: View {
  let game: PickemsGameRow
  let myPick: UUID?
  let pickPcts: [UUID: (count: Int, total: Int)]
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
        teamButton(teamId: game.awayTeamId, name: game.awayName, logo: game.awayLogoUrl, points: game.awayPoints)
        teamButton(teamId: game.homeTeamId, name: game.homeName, logo: game.homeLogoUrl, points: game.homePoints)
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
  private func teamButton(teamId: UUID, name: String?, logo: String?, points: Int?) -> some View {
    let picked = myPick == teamId
    let isWinner = game.isFinal && game.winnerTeamId == teamId
    let pctInfo = pickPcts[teamId]
    let pct: Int? = (pctInfo?.total ?? 0) > 0 ? Int((Double(pctInfo?.count ?? 0) / Double(pctInfo!.total) * 100).rounded()) : nil
    Button {
      onPick(teamId)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 9) {
          RetryingAsyncImage(url: logo.flatMap { URL(string: $0) }) { img in
            img.resizable().scaledToFit()
          } placeholder: {
            Image(systemName: "football").resizable().scaledToFit().opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
          }
          .frame(width: 30, height: 30)
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
        if let pct {
          VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                Capsule().fill(picked ? BoldTheme.Colors.green : Color.black.opacity(0.28))
                  .frame(width: geo.size.width * CGFloat(pct) / 100)
              }
            }
            .frame(height: 4)
            Text("\(pct)% picked")
              .font(BoldTheme.Fonts.mono(9.5))
              .foregroundColor(BoldTheme.Colors.textFaint)
          }
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
