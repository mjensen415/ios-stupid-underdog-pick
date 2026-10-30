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
  // Only populated for a group-scoped week view (see
  // WeeklyLeaderboardViewModel.fetchRows) -- nil means either not
  // applicable (season view, global view) or not yet locked/no pick.
  var pickLabel: String? = nil
}

struct LeaderboardHeaderRow: View {
  var body: some View {
    HStack {
      Text("Rank")
        .frame(width: 44, alignment: .leading)
      Text("Player")
      Spacer()
      Text("Points")
    }
    .font(BoldTheme.Fonts.body(12, weight: .semibold))
    .foregroundColor(BoldTheme.Colors.textDim)
    .listRowInsets(EdgeInsets(top: 12, leading: 32, bottom: 8, trailing: 32))
    .listRowSeparator(.hidden)
    // Always the top row of the ranked list -- rounds only the top corners
    // so it fuses with the LeaderboardRows below into one card, matching
    // the day-group card treatment on the games screen.
    .listRowBackground(
      UnevenRoundedRectangle(topLeadingRadius: BoldTheme.Radius.card, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: BoldTheme.Radius.card, style: .continuous)
        .fill(BoldTheme.Colors.card)
        .padding(.horizontal, BoldTheme.Space.margin)
    )
  }
}

struct LeaderboardRow: View {
  let rank: Int
  let userId: UUID
  let name: String
  let record: String
  let points: String
  var pickLabel: String? = nil
  // Last row in the ranked list -- rounds the bottom corners to close out
  // the card that LeaderboardHeaderRow opens at the top.
  var isLast: Bool = false

  var body: some View {
    NavigationLink(destination: PublicProfileView(userId: userId)) {
      HStack(alignment: .center, spacing: 16) {
        Text(verbatim: "\(rank)")
          .font(BoldTheme.TypeRole.tableNumber(14))
          .foregroundColor(BoldTheme.Colors.text)
          .frame(width: 28, alignment: .leading)

        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .font(BoldTheme.Fonts.body(15, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
          Text(record)
            .font(BoldTheme.TypeRole.tableNumber(12, weight: .regular))
            .foregroundColor(BoldTheme.Colors.textDim)
          if let pickLabel {
            Text(pickLabel)
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(BoldTheme.Colors.textDim)
          }
        }

        Spacer()

        Text(points)
          .font(BoldTheme.TypeRole.tableNumber(15))
          // Ink table number (de-slop colour roles: no gold/green decoration).
          .foregroundColor(BoldTheme.Colors.text)
      }
    }
    .padding(.vertical, 12)
    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
    .listRowSeparator(.hidden)
    .listRowBackground(
      UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: isLast ? BoldTheme.Radius.card : 0, bottomTrailingRadius: isLast ? BoldTheme.Radius.card : 0, topTrailingRadius: 0, style: .continuous)
        .fill(BoldTheme.Colors.card)
        .overlay(alignment: .top) { Rectangle().fill(BoldTheme.Colors.border).frame(height: 1).padding(.horizontal, 16) }
        .padding(.horizontal, BoldTheme.Space.margin)
    )
  }
}
