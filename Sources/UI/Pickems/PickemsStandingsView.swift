import SwiftUI
import Supabase

enum PickemsScope { case week, season }

// Mirrors get_pickems_weekly_leaderboard's own tiebreak_key SQL exactly:
// closest-without-going-over wins, a busted guess ranks below every valid
// one, no guess at all ranks last of all. Equal keys share a rank -- "two
// winners that week" shows up as both players at the same rank number.
// Same logic as web's PickemsStandings.tsx rankRows(). Internal (not
// private) -- PickemsView's at-a-glance strip reuses this exact ranking.
struct RankedRow: Identifiable {
  let row: GroupPickemsRow
  let rank: Int
  var id: UUID { row.userId }
}

func rankRows(_ rows: [GroupPickemsRow], scope: PickemsScope, actualTotal: Int?) -> [RankedRow] {
  func tiebreakKey(_ r: GroupPickemsRow) -> Int {
    guard scope == .week, let actualTotal else { return 0 }
    guard let guess = r.guessedTotalPoints else { return 2_000_000_000 }
    if guess <= actualTotal { return actualTotal - guess }
    return 1_000_000_000 + (guess - actualTotal)
  }
  func correct(_ r: GroupPickemsRow) -> Int { scope == .week ? r.weekCorrect : r.seasonCorrect }

  let sorted = rows.sorted { a, b in
    let ca = correct(a), cb = correct(b)
    if ca != cb { return ca > cb }
    return tiebreakKey(a) < tiebreakKey(b)
  }

  var result: [RankedRow] = []
  var rank = 0
  var prevKey: String?
  for (i, r) in sorted.enumerated() {
    let key = "\(correct(r))|\(scope == .week ? tiebreakKey(r) : 0)"
    if key != prevKey { rank = i + 1; prevKey = key }
    result.append(RankedRow(row: r, rank: rank))
  }
  return result
}

struct PickemsStandingsView: View {
  let season: Int?
  let week: Int?
  let lastGame: PickemsGameRow?
  // When set, standings are scoped to this one group directly -- no
  // membership fetch, no group picker, no "no groups yet" empty state.
  // Used when this view is embedded on a specific group's own detail page.
  let fixedGroupId: UUID?

  @Environment(\.supabaseClient) private var client
  @State private var myGroups: [MyGroup]?
  @State private var selectedGroupId: UUID?
  @State private var scope: PickemsScope = .week
  @State private var rows: [GroupPickemsRow] = []
  @State private var isLoading = false
  @State private var picksByUser: [UUID: [UUID: GroupPickRow]] = [:]
  @State private var matrixGames: [UUID: MatrixGameInfo] = [:]
  @State private var gameOrder: [UUID] = []

  init(season: Int?, week: Int?, lastGame: PickemsGameRow?, fixedGroupId: UUID? = nil) {
    self.season = season
    self.week = week
    self.lastGame = lastGame
    self.fixedGroupId = fixedGroupId
    self._selectedGroupId = State(initialValue: fixedGroupId)
    self._myGroups = State(initialValue: fixedGroupId != nil ? [] : nil)
  }

  private var lastGameActualTotal: Int? {
    guard let lastGame, lastGame.isFinal, let h = lastGame.homePoints, let a = lastGame.awayPoints else { return nil }
    return h + a
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if fixedGroupId == nil && myGroups == nil {
        Text("Loading…").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textFaint).padding(.top, 40)
      } else if fixedGroupId == nil && myGroups?.isEmpty == true {
        emptyState
      } else {
        if fixedGroupId == nil, (myGroups?.count ?? 0) > 1 { groupPicker }
        scopeToggle
        if scope == .week, let lastGame {
          Text("Tiebreaker: combined score, \(lastGame.awayName ?? "") @ \(lastGame.homeName ?? "")\(lastGameActualTotal.map { " — final: \($0)" } ?? "")")
            .font(BoldTheme.Fonts.body(11.5))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
        standingsList
      }
    }
    .padding(.top, 16)
    .task { await loadGroups() }
    .task(id: "\(selectedGroupId?.uuidString ?? "")|\(scope)|\(season ?? 0)|\(week ?? 0)") {
      await loadStandings()
      if scope == .week, let groupId = selectedGroupId, let season, let week {
        await loadPickMatrix(groupId: groupId, season: season, week: week)
      } else {
        picksByUser = [:]; matrixGames = [:]; gameOrder = []
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Text("NO GROUPS YET").font(BoldTheme.Fonts.display(22)).foregroundColor(BoldTheme.Colors.text)
      Text("Pickems standings are group-only — join or start a group to see where you stack up.")
        .font(BoldTheme.Fonts.body(13))
        .foregroundColor(BoldTheme.Colors.textDim)
        .multilineTextAlignment(.center)
      NavigationLink(destination: GroupsListView()) {
        Text("Find a group")
          .font(BoldTheme.Fonts.body(13, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
          .padding(.horizontal, 20).padding(.vertical, 10)
          .background(BoldTheme.Colors.gold)
          .clipShape(Capsule())
      }
    }
    .frame(maxWidth: .infinity)
    .padding(32)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var groupPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(myGroups ?? []) { g in
          let active = g.group_id == selectedGroupId
          Button {
            selectedGroupId = g.group_id
          } label: {
            Text(g.name)
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
  }

  private var scopeToggle: some View {
    HStack(spacing: 6) {
      ForEach([PickemsScope.week, .season], id: \.self) { s in
        let active = scope == s
        Button {
          scope = s
        } label: {
          Text(s == .week ? "This Week" : "Season")
            .font(BoldTheme.Fonts.body(12, weight: .bold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(active ? BoldTheme.Colors.green : Color.clear)
            .foregroundColor(active ? .white : BoldTheme.Colors.textDim)
            .overlay(Capsule().strokeBorder(active ? BoldTheme.Colors.green : BoldTheme.Colors.border, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  // Only games at least one member's pick has actually locked for -- an
  // upcoming game with zero locked picks has nothing worth a column yet.
  private var lockedGameIds: [UUID] {
    gameOrder.filter { gameId in picksByUser.values.contains { $0[gameId]?.isLocked == true } }
  }

  @ViewBuilder private var standingsList: some View {
    let ranked = rankRows(rows, scope: scope, actualTotal: scope == .week ? lastGameActualTotal : nil)
    if isLoading {
      Text("Loading standings…").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textFaint).padding(.top, 24)
    } else if ranked.isEmpty {
      Text("No picks yet in this group.").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textFaint).padding(.top, 24)
    } else {
      HStack(alignment: .top, spacing: 0) {
        // Pinned rank/entry/pts column
        VStack(spacing: 0) {
          HStack {
            Text("RK").frame(width: 22, alignment: .leading)
            Text("ENTRY")
            Spacer()
            Text("PTS")
          }
          .font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
          .padding(.horizontal, 16).frame(height: 52)

          Divider().background(BoldTheme.Colors.border)

          ForEach(Array(ranked.enumerated()), id: \.element.id) { i, r in
            let correct = scope == .week ? r.row.weekCorrect : r.row.seasonCorrect
            HStack(alignment: .center, spacing: 0) {
              Text("\(r.rank)").frame(width: 22, alignment: .leading).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textFaint)
              Text(r.row.displayName).font(BoldTheme.Fonts.body(14, weight: .semibold)).foregroundColor(BoldTheme.Colors.text).lineLimit(1)
              Spacer(minLength: 4)
              Text("\(correct)")
                .font(BoldTheme.Fonts.display(20))
                .foregroundColor(r.rank == 1 ? BoldTheme.Colors.goldDeep : BoldTheme.Colors.green)
            }
            .padding(.horizontal, 16).frame(height: 52)
            if i != ranked.count - 1 { Divider().background(BoldTheme.Colors.border) }
          }
        }
        .frame(minWidth: 168, alignment: .leading)

        if scope == .week, !lockedGameIds.isEmpty {
          Divider().background(BoldTheme.Colors.border)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
              ForEach(lockedGameIds, id: \.self) { gameId in
                if let g = matrixGames[gameId] {
                  VStack(spacing: 0) {
                    VStack(spacing: 1) {
                      Text("\(g.awayShort)@\(g.homeShort)").font(BoldTheme.Fonts.mono(10, weight: .bold))
                      if g.status == "final", let hp = g.homePoints, let ap = g.awayPoints {
                        Text("\(ap)-\(hp)").font(BoldTheme.Fonts.mono(8.5)).foregroundColor(BoldTheme.Colors.textFaint)
                      }
                    }
                    .frame(width: 60, height: 52)

                    Divider().background(BoldTheme.Colors.border)

                    ForEach(Array(ranked.enumerated()), id: \.element.id) { i, r in
                      MatrixCellView(pick: picksByUser[r.row.userId]?[gameId], game: g)
                        .frame(width: 60, height: 52)
                      if i != ranked.count - 1 { Divider().background(BoldTheme.Colors.border) }
                    }
                  }
                  Divider().background(BoldTheme.Colors.border)
                }
              }
            }
          }
        }
      }
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
  }

  private func loadGroups() async {
    guard fixedGroupId == nil else { return }
    guard let client else { return }
    do {
      // Only groups actually playing Pickems -- an underdog-only group's
      // Pickems board would just always be empty, so it's not a real option.
      let groups = try await GroupsService(client: client).fetchMyGroups()
        .filter { $0.game_type == .pickems || $0.game_type == .both }
      myGroups = groups
      if selectedGroupId == nil {
        selectedGroupId = groups.first?.group_id
      }
    } catch {
      myGroups = []
    }
  }

  private func loadStandings() async {
    guard let client, let groupId = selectedGroupId, let season else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      rows = try await PickemsService(client: client).fetchGroupLeaderboard(
        groupId: groupId, season: season, week: scope == .week ? week : nil
      )
    } catch {
      rows = []
    }
  }

  // Picks were previously visible to no one but the picker themself, even
  // after the game locked -- get_group_pickems_picks (SECURITY DEFINER,
  // bypasses pickems_picks' self-only RLS) nulls out picked_team_id for
  // any game that hasn't locked yet.
  private struct MatrixGameRow: Decodable {
    struct TeamShort: Decodable { let short_name: String? }
    let id: UUID
    let status: String
    let home_points: Int?
    let away_points: Int?
    let home_team_id: UUID
    let away_team_id: UUID
    let home: TeamShort?
    let away: TeamShort?
  }

  private func loadPickMatrix(groupId: UUID, season: Int, week: Int) async {
    guard let client else { return }
    do {
      async let picksTask: [GroupPickRow] = PickemsService(client: client).fetchGroupPicks(groupId: groupId, season: season, week: week)
      async let gamesTask: [MatrixGameRow] = client
        .from("games")
        .select("id, status, home_points, away_points, home_team_id, away_team_id, home:teams!games_home_team_id_fkey(short_name), away:teams!games_away_team_id_fkey(short_name)")
        .eq("season", value: season).eq("week", value: week).eq("sport", value: "nfl")
        .order("start_time", ascending: true)
        .execute()
        .value
      let (picks, games) = try await (picksTask, gamesTask)

      var byUser: [UUID: [UUID: GroupPickRow]] = [:]
      for p in picks {
        guard let gameId = p.gameId else { continue }
        byUser[p.userId, default: [:]][gameId] = p
      }
      picksByUser = byUser

      var gameMap: [UUID: MatrixGameInfo] = [:]
      var order: [UUID] = []
      for g in games {
        order.append(g.id)
        gameMap[g.id] = MatrixGameInfo(
          homeTeamId: g.home_team_id, awayTeamId: g.away_team_id,
          homeShort: g.home?.short_name ?? "?", awayShort: g.away?.short_name ?? "?",
          homePoints: g.home_points, awayPoints: g.away_points, status: g.status
        )
      }
      matrixGames = gameMap
      gameOrder = order
    } catch {
      picksByUser = [:]; matrixGames = [:]; gameOrder = []
    }
  }
}

struct MatrixGameInfo {
  let homeTeamId: UUID
  let awayTeamId: UUID
  let homeShort: String
  let awayShort: String
  let homePoints: Int?
  let awayPoints: Int?
  let status: String
}

private struct MatrixCellView: View {
  let pick: GroupPickRow?
  let game: MatrixGameInfo

  var body: some View {
    Group {
      if pick?.isLocked != true {
        Circle().fill(Color.black.opacity(0.06)).frame(width: 24, height: 24).overlay(
          Image(systemName: "lock.fill").font(.system(size: 9)).foregroundColor(BoldTheme.Colors.textFaint)
        )
      } else if let teamId = pick?.pickedTeamId {
        let winnerTeamId: UUID? = {
          guard game.status == "final", let hp = game.homePoints, let ap = game.awayPoints else { return nil }
          if hp > ap { return game.homeTeamId }
          if ap > hp { return game.awayTeamId }
          return nil
        }()
        let correct = winnerTeamId != nil && winnerTeamId == teamId
        let short = teamId == game.homeTeamId ? game.homeShort : game.awayShort
        HStack(spacing: 3) {
          Text(short).font(BoldTheme.Fonts.mono(10, weight: .bold))
          if winnerTeamId != nil {
            Image(systemName: correct ? "checkmark" : "xmark").font(.system(size: 8, weight: .bold))
          }
        }
        .foregroundColor(winnerTeamId == nil ? BoldTheme.Colors.textDim : (correct ? BoldTheme.Colors.green : Color(hex: 0xC6402A)))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(
          Capsule().fill(winnerTeamId == nil ? Color.black.opacity(0.06) : (correct ? BoldTheme.Colors.green.opacity(0.14) : Color(hex: 0xC6402A).opacity(0.12)))
        )
      } else {
        Text("—").font(BoldTheme.Fonts.mono(11)).foregroundColor(BoldTheme.Colors.textFaint)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
