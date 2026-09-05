import SwiftUI
import Supabase

struct MainTabView: View {
  @EnvironmentObject var appState: AppState
  @State private var selection = 0

  init() {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(BoldTheme.Colors.bgPage)
    let normal = UITabBarItemAppearance()
    normal.normal.iconColor = UIColor(BoldTheme.Colors.textFaint)
    normal.normal.titleTextAttributes = [.foregroundColor: UIColor(BoldTheme.Colors.textFaint)]
    normal.selected.iconColor = UIColor(BoldTheme.Colors.goldDeep)
    normal.selected.titleTextAttributes = [.foregroundColor: UIColor(BoldTheme.Colors.goldDeep)]
    appearance.stackedLayoutAppearance = normal
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
  }

  var body: some View {
    TabView(selection: $selection) {
      HomeView()
        .tabItem { Label("Home", systemImage: "house") }
        .tag(0)

      GamesTab()
        .tabItem { Label("Games", systemImage: "sportscourt") }
        .tag(1)

      MyPicksView()
        .tabItem { Label("My Pick", systemImage: "checkmark.seal") }
        .tag(3)

      GroupsListView()
        .tabItem { Label("Groups", systemImage: "person.3.fill") }
        .tag(4)

      ProfileView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(5)
    }
    .tint(BoldTheme.Colors.goldDeep)
    .onChange(of: appState.requestedTab) { _, newValue in
      guard let newValue else { return }
      selection = newValue
      appState.requestedTab = nil
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

