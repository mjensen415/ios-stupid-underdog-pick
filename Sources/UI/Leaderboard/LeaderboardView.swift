import SwiftUI

struct LeaderboardView: View {
  @State private var selection: Int = 0 // 0 weekly, 1 season

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Mode", selection: $selection) {
          Text("Weekly").tag(0)
          Text("Season").tag(1)
        }
        .pickerStyle(.segmented)
        .padding()

        if selection == 0 {
          WeeklyLeaderboardView()
        } else {
          SeasonLeaderboardView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
      .navigationTitle(selection == 0 ? "Weekly Leaderboard" : "Season")
      .toolbarBackground(BoldTheme.Colors.bgPage, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      // Frost's bgPage is light now (was dark under Bold), so nav bar
      // chrome (title/buttons) needs the light color scheme for contrast --
      // .dark would render light-on-light and be illegible.
      .toolbarColorScheme(.light, for: .navigationBar)
    }
    .tint(BoldTheme.Colors.gold)
  }
}

