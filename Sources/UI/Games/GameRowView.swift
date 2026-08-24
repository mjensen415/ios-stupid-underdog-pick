import SwiftUI

struct GameRowView: View {
  let game: Game
  let logoFor: (UUID?) -> URL?
  let isSelected: Bool

  private var isHomeFavorite: Bool {
    guard let fav = game.derivedFavoriteTeamId else { return false }
    return fav == game.homeTeamId
  }

  // Favorite/underdog decides left-vs-right; home/away is a separate axis
  // (the home team can land on either side depending on who's favored) --
  // whichever slot is showing the home team gets the "@" prefix, standard
  // sports notation for "Away @ Home".
  private var leftTeamName: String {
    let name = isHomeFavorite ? (game.homeTeam ?? "Home") : (game.awayTeam ?? "Away")
    return isHomeFavorite ? "@ \(name)" : name
  }
  private var rightTeamName: String {
    let name = isHomeFavorite ? (game.awayTeam ?? "Away") : (game.homeTeam ?? "Home")
    return isHomeFavorite ? name : "@ \(name)"
  }
  private var leftTeamId: UUID? {
    isHomeFavorite ? game.homeTeamId : game.awayTeamId
  }
  private var rightTeamId: UUID? {
    isHomeFavorite ? game.awayTeamId : game.homeTeamId
  }

  // Games span multiple days within a single week, so time alone isn't
  // enough to tell them apart at a glance -- weekday + date on one line,
  // kickoff time on the next.
  private var kickoffText: String {
    let day = DateFormatter()
    day.dateFormat = "EEE M/d"
    let time = DateFormatter()
    time.timeStyle = .short
    time.dateStyle = .none
    return "\(day.string(from: game.startTime))\n\(time.string(from: game.startTime))"
  }

  var body: some View {
    HStack(spacing: 12) {
      teamBlock(name: leftTeamName, logo: logoFor(leftTeamId))

      VStack(spacing: 4) {
        Text(kickoffText).font(BoldTheme.Fonts.mono(12)).foregroundColor(BoldTheme.Colors.textFaint).multilineTextAlignment(.center)
        if let bl = game.bettingLine, !bl.isEmpty {
          Text(bl).font(BoldTheme.Fonts.mono(13)).foregroundColor(BoldTheme.Colors.goldDeep)
        } else if let sp = game.underdogSpread {
          Text(String(format: "%.1f", sp)).font(BoldTheme.Fonts.mono(13)).foregroundColor(BoldTheme.Colors.goldDeep)
        } else {
          Text("—").font(BoldTheme.Fonts.mono(13)).foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      .frame(maxWidth: .infinity)

      ZStack(alignment: .topTrailing) {
        teamBlock(name: rightTeamName, logo: logoFor(rightTeamId))
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .imageScale(.medium)
            .foregroundColor(BoldTheme.Colors.gold)
            .padding(2)
        }
      }
    }
    .padding(.vertical, 14)
    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    .listRowSeparatorTint(BoldTheme.Colors.border)
    // A fixed-position bottom overlay here previously caused a "Picked" pill
    // to land at different relative heights depending on whether team names
    // wrapped to one or two lines, sometimes overlapping the spread/kickoff
    // column -- a full-row tint can't overlap anything since it isn't
    // positioned relative to variable content height. The checkmark badge on
    // the picked team's logo (below) is the primary "you picked this"
    // signal; the tint just reinforces it at a glance while scrolling.
    .listRowBackground(isSelected ? BoldTheme.Colors.gold.opacity(0.08) : BoldTheme.Colors.bgPage)
  }

  @ViewBuilder
  private func teamBlock(name: String, logo: URL?) -> some View {
    VStack(spacing: 6) {
      AsyncImage(url: logo) { phase in
        switch phase {
        case .success(let img): img.resizable().scaledToFit()
        default: Image(systemName: "football").resizable().scaledToFit().opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      .frame(width: 28, height: 28)
      Text(name)
        .font(BoldTheme.Fonts.body(12))
        .foregroundColor(BoldTheme.Colors.text)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .frame(width: 96)
  }
}

