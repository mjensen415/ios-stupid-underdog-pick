import SwiftUI

struct GameRowView: View {
  let game: Game
  let logoFor: (UUID?) -> URL?
  let isSelected: Bool

  private var isHomeFavorite: Bool {
    guard let fav = game.favoriteTeamId else { return false }
    return fav == game.homeTeamId
  }

  private var leftTeamName: String {
    isHomeFavorite ? (game.homeTeam ?? "Home") : (game.awayTeam ?? "Away")
  }
  private var rightTeamName: String {
    isHomeFavorite ? (game.awayTeam ?? "Away") : (game.homeTeam ?? "Home")
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
        Text(kickoffText).font(.subheadline).foregroundStyle(.secondary)
        if let bl = game.bettingLine, !bl.isEmpty {
          Text(bl).font(.footnote.monospaced())
        } else if let sp = game.latestSpread {
          Text(String(format: "Spread: %.1f", sp)).font(.footnote.monospaced())
        } else {
          Text("—").font(.footnote).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity)

      ZStack(alignment: .topTrailing) {
        teamBlock(name: rightTeamName, logo: logoFor(rightTeamId))
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .imageScale(.medium)
            .padding(2)
        }
      }
    }
    .padding(.vertical, 8)
    .overlay(alignment: .bottom) {
      if isSelected {
        Text("Picked")
          .font(.caption2.bold())
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(Capsule().fill(.blue.opacity(0.15)))
          .foregroundStyle(.blue)
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
        default: Image(systemName: "football").resizable().scaledToFit().opacity(0.3)
        }
      }
      .frame(width: 28, height: 28)
      Text(name).font(.footnote).lineLimit(2).multilineTextAlignment(.center)
    }
    .frame(width: 96)
  }
}

