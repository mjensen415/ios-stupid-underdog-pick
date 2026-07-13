import SwiftUI
import Supabase

struct MainTabView: View {
  var body: some View {
    TabView {
      GamesTab()
        .tabItem { Label("Games", systemImage: "sportscourt") }

      LeaderboardView()
        .tabItem { Label("Leaders", systemImage: "list.number") }

      MyPicksView()
        .tabItem { Label("My Pick", systemImage: "checkmark.seal") }

      ProfileView()
        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
    }
  }
}

private struct GamesTab: View {
  @Environment(\.supabaseClient) private var client
  var body: some View {
    if let client {
      GamesView(viewModel: .init(client: client))
    } else {
      Text("Missing client")
    }
  }
}

