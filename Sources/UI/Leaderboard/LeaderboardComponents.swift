import SwiftUI

// Shared spacing language for both leaderboard screens -- open, hairline-
// divided rows (mirrors winner-circle-dev's Leaderboard.tsx / the Splash
// Sports reference the design direction is modeled on), not boxed cards.

struct LeaderboardHeaderRow: View {
  var body: some View {
    HStack {
      Text("RK")
        .frame(width: 28, alignment: .leading)
      Text("ENTRY")
      Spacer()
      Text("PTS")
    }
    .font(BoldTheme.Fonts.mono(11))
    .tracking(0.9)
    .foregroundColor(BoldTheme.Colors.textFaint)
    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
    .listRowSeparatorTint(BoldTheme.Colors.border)
    .listRowBackground(BoldTheme.Colors.bgPage)
  }
}

struct LeaderboardRow: View {
  let rank: Int
  let name: String
  let record: String
  let points: String

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      Text("\(rank)")
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.textFaint)
        .frame(width: 28, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(BoldTheme.Fonts.body(15, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
        Text(record)
          .font(BoldTheme.Fonts.mono(11))
          .foregroundColor(BoldTheme.Colors.textFaint)
      }

      Spacer()

      Text(points)
        .font(BoldTheme.Fonts.display(22))
        .foregroundColor(BoldTheme.Colors.gold)
    }
    .padding(.vertical, 12)
    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    .listRowSeparatorTint(BoldTheme.Colors.border)
    .listRowBackground(BoldTheme.Colors.bgPage)
  }
}
