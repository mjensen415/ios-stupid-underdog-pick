import SwiftUI
import Supabase

struct MainTabView: View {
  @EnvironmentObject var appState: AppState
  @State private var selection = 0

  init() {
    // iOS 26: leave the stock Liquid Glass tab bar alone (de-slop #28) --
    // an opaque UITabBarAppearance fights the glass and hides the content
    // scrolling under it. Only the tints below are ours there.
    if #available(iOS 26, *) { return }
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()
    appearance.backgroundColor = UIColor(BoldTheme.Colors.bgPage).withAlphaComponent(0.82)
    let normal = UITabBarItemAppearance()
    normal.normal.iconColor = UIColor(BoldTheme.Colors.textDim)
    normal.normal.titleTextAttributes = [.foregroundColor: UIColor(BoldTheme.Colors.textDim)]
    normal.selected.iconColor = UIColor(BoldTheme.Colors.text)
    normal.selected.titleTextAttributes = [.foregroundColor: UIColor(BoldTheme.Colors.text)]
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
        .tabItem { Label(appState.hpSport == nil && appState.currentGame == .pickems ? "Pick" : "Games", systemImage: "sportscourt") }
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
    // Selected tab in ink (mock: active tab is ink, others dim); gold is
    // kept for "your next action" only.
    .tint(BoldTheme.Colors.text)
    .onChange(of: appState.requestedTab) { _, newValue in
      guard let newValue else { return }
      selection = newValue
      appState.requestedTab = nil
    }
  }
}

// CFB Underdog, Pro Ball Underdog, and Pickems are separate contests --
// this tab's slot follows appState.currentGame the same way web's
// second-tier nav resolves "Games"/"Pick" to /games or /pickems, so
// Pickems is a genuine peer reachable right from the tab bar instead of
// only through Home's "Switch Game" sheet or a banner.
private struct GamesTab: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.supabaseClient) private var client
  var body: some View {
    if let hp = appState.hpSport {
      SportLeagueView(sport: hp)
        .id(hp)
    } else if appState.currentGame == .pickems {
      PickemsView()
    } else if let client {
      GamesView(viewModel: .init(client: client))
    } else {
      Text("Missing client")
    }
  }
}

