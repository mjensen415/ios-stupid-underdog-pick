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

  private var kickoffText: String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: game.startTime)
  }

  var body: some View {
    HStack(spacing: 12) {
      teamBlock(name: leftTeamName, logo: logoFor(leftTeamId))

      VStack(spacing: 4) {
        Text(kickoffText).font(BoldTheme.Fonts.mono(12)).foregroundColor(BoldTheme.Colors.textFaint)
        if let bl = game.bettingLine, !bl.isEmpty {
          Text(bl).font(BoldTheme.Fonts.mono(13)).foregroundColor(BoldTheme.Colors.gold)
        } else if let sp = game.underdogSpread {
          Text(String(format: "%.1f", sp)).font(BoldTheme.Fonts.mono(13)).foregroundColor(BoldTheme.Colors.gold)
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
    .padding(.vertical, 8)
    .listRowBackground(BoldTheme.Colors.bgPage)
    .overlay(alignment: .bottom) {
      if isSelected {
        Text("PICKED")
          .font(BoldTheme.Fonts.mono(10))
          .tracking(0.6)
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(Capsule().fill(BoldTheme.Colors.gold.opacity(0.15)))
          .foregroundColor(BoldTheme.Colors.gold)
          .padding(.bottom, 4)
      }
    }
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

