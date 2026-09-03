import SwiftUI
import Supabase

private enum PickemsScope { case week, season }

// Mirrors get_pickems_weekly_leaderboard's own tiebreak_key SQL exactly:
// closest-without-going-over wins, a busted guess ranks below every valid
// one, no guess at all ranks last of all. Equal keys share a rank -- "two
// winners that week" shows up as both players at the same rank number.
// Same logic as web's PickemsStandings.tsx rankRows().
private struct RankedRow: Identifiable {
  let row: GroupPickemsRow
  let rank: Int
  var id: UUID { row.userId }
}

private func rankRows(_ rows: [GroupPickemsRow], scope: PickemsScope, actualTotal: Int?) -> [RankedRow] {
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

  @ViewBuilder private var standingsList: some View {
    let ranked = rankRows(rows, scope: scope, actualTotal: scope == .week ? lastGameActualTotal : nil)
    if isLoading {
      Text("Loading standings…").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textFaint).padding(.top, 24)
    } else if ranked.isEmpty {
      Text("No picks yet in this group.").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textFaint).padding(.top, 24)
    } else {
      VStack(spacing: 0) {
        HStack {
          Text("RK").frame(width: 28, alignment: .leading)
          Text("ENTRY")
          Spacer()
          Text("PTS")
        }
        .font(BoldTheme.Fonts.mono(10.5)).foregroundColor(BoldTheme.Colors.textFaint)
        .padding(.horizontal, 16).padding(.vertical, 10)

        Divider().background(BoldTheme.Colors.border)

        ForEach(Array(ranked.enumerated()), id: \.element.id) { i, r in
          let correct = scope == .week ? r.row.weekCorrect : r.row.seasonCorrect
          let total = scope == .week ? r.row.weekTotalPicks : r.row.seasonTotalPicks
          HStack(alignment: .center, spacing: 0) {
            Text("\(r.rank)").frame(width: 28, alignment: .leading).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textFaint)
            VStack(alignment: .leading, spacing: 1) {
              Text(r.row.displayName).font(BoldTheme.Fonts.body(14.5, weight: .semibold)).foregroundColor(BoldTheme.Colors.text).lineLimit(1)
              Text("\(correct)-\(max(total - correct, 0))\(scope == .week && r.row.guessedTotalPoints != nil ? " · guessed \(r.row.guessedTotalPoints!)" : "")")
                .font(BoldTheme.Fonts.mono(11)).foregroundColor(BoldTheme.Colors.textFaint)
            }
            Spacer()
            Text("\(correct)")
              .font(BoldTheme.Fonts.display(22))
              .foregroundColor(r.rank == 1 ? BoldTheme.Colors.goldDeep : BoldTheme.Colors.green)
          }
          .padding(.horizontal, 16).padding(.vertical, 12)
          if i != ranked.count - 1 { Divider().background(BoldTheme.Colors.border) }
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
}
