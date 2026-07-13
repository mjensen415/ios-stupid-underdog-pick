import SwiftUI

struct LeaderboardView: View {
  @State private var selection: Int = 0 // 0 weekly, 1 season

  var body: some View {
    NavigationStack {
      VStack {
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
      .navigationTitle("Leaderboard")
    }
  }
}

