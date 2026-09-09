import SwiftUI
import Supabase

// Picks were previously visible to no one but the picker themself, even
// after the game locked -- get_group_pickems_picks (SECURITY DEFINER,
// bypasses pickems_picks' self-only RLS) nulls out picked_team_id for any
// game that hasn't locked yet, so this only ever renders games that already
// have. Mirrors web's WeekPicksReveal in PickemsStandings.tsx.
struct WeekPicksRevealView: View {
  let groupId: UUID
  let season: Int
  let week: Int

  @Environment(\.supabaseClient) private var client
  @State private var rows: [GroupPickRow]?
  @State private var games: [UUID: PickemsGameRow] = [:]

  private var lockedGameIds: [UUID] {
    guard let rows else { return [] }
    var seen = Set<UUID>()
    var ordered: [UUID] = []
    for r in rows where r.isLocked {
      guard let gameId = r.gameId, !seen.contains(gameId) else { continue }
      seen.insert(gameId)
      ordered.append(gameId)
    }
    return ordered
  }

  var body: some View {
    Group {
      if let rows, !lockedGameIds.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("PICKS (LOCKED GAMES)")
            .font(BoldTheme.Fonts.mono(10.5))
            .tracking(0.9)
            .foregroundColor(BoldTheme.Colors.textFaint)
            .padding(.top, 20)

          ForEach(lockedGameIds, id: \.self) { gameId in
            if let g = games[gameId] {
              gameCard(gameId: gameId, game: g, rows: rows.filter { $0.gameId == gameId })
            }
          }
        }
      }
    }
    .task(id: "\(groupId.uuidString)|\(season)|\(week)") { await load() }
  }

  private func gameCard(gameId: UUID, game: PickemsGameRow, rows: [GroupPickRow]) -> some View {
    var byTeam: [UUID: [String]] = [:]
    var noPick: [String] = []
    for r in rows {
      guard let teamId = r.pickedTeamId else { noPick.append(r.displayName); continue }
      byTeam[teamId, default: []].append(r.displayName)
    }

    return VStack(alignment: .leading, spacing: 4) {
      Text("\(game.awayName ?? "Away") @ \(game.homeName ?? "Home")")
        .font(BoldTheme.Fonts.body(12, weight: .bold))
        .foregroundColor(BoldTheme.Colors.text)

      ForEach([game.awayTeamId, game.homeTeamId], id: \.self) { teamId in
        if let names = byTeam[teamId], !names.isEmpty {
          let teamName = teamId == game.homeTeamId ? (game.homeName ?? "") : (game.awayName ?? "")
          (Text(teamName + ": ").font(BoldTheme.Fonts.body(12.5, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
            + Text(names.joined(separator: ", ")).font(BoldTheme.Fonts.body(12.5)).foregroundColor(BoldTheme.Colors.textDim))
        }
      }
      if !noPick.isEmpty {
        (Text("No pick: ").font(BoldTheme.Fonts.body(12.5, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
          + Text(noPick.joined(separator: ", ")).font(BoldTheme.Fonts.body(12.5)).foregroundColor(BoldTheme.Colors.textFaint))
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func load() async {
    guard let client else { return }
    do {
      async let picksTask = PickemsService(client: client).fetchGroupPicks(groupId: groupId, season: season, week: week)
      async let gamesTask = PickemsService(client: client).fetchGames(season: season, week: week)
      let (picks, gameRows) = try await (picksTask, gamesTask)
      rows = picks
      games = Dictionary(uniqueKeysWithValues: gameRows.map { ($0.id, $0) })
    } catch {
      rows = []
    }
  }
}
