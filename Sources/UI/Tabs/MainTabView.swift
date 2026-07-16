import SwiftUI
import Supabase

struct MainTabView: View {
  init() {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(BoldTheme.Colors.bgPage)
    let normal = UITabBarItemAppearance()
    normal.normal.iconColor = UIColor(BoldTheme.Colors.textFaint)
    normal.normal.titleTextAttributes = [.foregroundColor: UIColor(BoldTheme.Colors.textFaint)]
    normal.selected.iconColor = UIColor(BoldTheme.Colors.gold)
    normal.selected.titleTextAttributes = [.foregroundColor: UIColor(BoldTheme.Colors.gold)]
    appearance.stackedLayoutAppearance = normal
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
  }

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
    .tint(BoldTheme.Colors.gold)
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

