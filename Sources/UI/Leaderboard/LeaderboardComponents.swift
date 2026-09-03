import SwiftUI

// Shared spacing language for both leaderboard screens -- open, hairline-
// divided rows (mirrors winner-circle-dev's Leaderboard.tsx / the Splash
// Sports reference the design direction is modeled on), not boxed cards.

// Global (every eligible player) vs one specific group's own standings --
// mirrors web's Leaderboard.tsx boardScope state exactly.
enum LeaderboardBoardScope: Hashable {
  case global
  case group
}

/// Unified row shape both WeeklyLeaderboardView and SeasonLeaderboardView
/// render into a LeaderboardRow, whether the data came from the global
/// get_weekly_leaderboard/get_season_leaderboard RPCs or from one group's
/// groups-leaderboard edge function -- callers just map either source into
/// this before handing rows to the list.
struct LeaderboardDisplayRow: Identifiable {
  let id: UUID
  let userId: UUID
  let name: String
  let record: String
  let points: Double
}

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
    // Always the top row of the ranked list -- rounds only the top corners
    // so it fuses with the LeaderboardRows below into one card, matching
    // the day-group card treatment on the games screen.
    .listRowBackground(
      UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 16)
        .fill(BoldTheme.Colors.glassStrong)
    )
  }
}

struct LeaderboardRow: View {
  let rank: Int
  let userId: UUID
  let name: String
  let record: String
  let points: String
  // Last row in the ranked list -- rounds the bottom corners to close out
  // the card that LeaderboardHeaderRow opens at the top.
  var isLast: Bool = false

  var body: some View {
    NavigationLink(destination: PublicProfileView(userId: userId)) {
      HStack(alignment: .center, spacing: 16) {
        Text(verbatim: "\(rank)")
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
          // Gold reserved for rank #1 down a ranked list -- everything else
          // is GREEN, matching web's Leaderboard.tsx (`index === 0 ? GOLD :
          // GREEN`). Avoids gold-for-every-row diluting the highlight.
          .foregroundColor(rank == 1 ? BoldTheme.Colors.goldDeep : BoldTheme.Colors.green)
      }
    }
    .padding(.vertical, 12)
    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    .listRowSeparatorTint(BoldTheme.Colors.border)
    .listRowBackground(
      UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: isLast ? 16 : 0, bottomTrailingRadius: isLast ? 16 : 0, topTrailingRadius: 0)
        .fill(BoldTheme.Colors.glassStrong)
    )
  }
}
