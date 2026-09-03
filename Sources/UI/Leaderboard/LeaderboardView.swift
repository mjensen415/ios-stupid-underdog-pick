import SwiftUI
import Supabase

@MainActor
final class LeaderboardScopeViewModel: ObservableObject {
  @Published var sport: String = "cfb"
  @Published var boardScope: LeaderboardBoardScope = .global
  @Published var myGroups: [MyGroup] = []
  @Published var selectedGroupSlug: String?

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  // Silent on failure -- Global scope (the default) works fine with no
  // groups loaded, so a groups-mine hiccup shouldn't block the screen.
  func loadGroups() async {
    guard let client else { return }
    do {
      let groups = try await GroupsService(client: client).fetchMyGroups()
      myGroups = groups
      if selectedGroupSlug == nil { selectedGroupSlug = groups.first?.slug }
    } catch {
      #if DEBUG
      print("[LeaderboardScope][ERR]", error.localizedDescription)
      #endif
    }
  }
}

struct LeaderboardView: View {
  @Environment(\.supabaseClient) private var client
  @StateObject private var scopeVM = LeaderboardScopeViewModel()
  @State private var selection: Int = 0 // 0 weekly, 1 season

  // nil = global board; a slug scopes both sub-screens to that group's own
  // members-only standings, matching web's boardScope/selectedGroupSlug.
  private var activeGroupSlug: String? {
    scopeVM.boardScope == .group ? scopeVM.selectedGroupSlug : nil
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        PillToggle(
          options: [(label: "🏈 CFB", value: "cfb"), (label: "🏈 PRO BALL", value: "nfl")],
          selection: $scopeVM.sport
        )
        .padding(.horizontal)
        .padding(.top, 8)

        if !scopeVM.myGroups.isEmpty {
          PillToggle(
            options: [(label: "Global", value: LeaderboardBoardScope.global), (label: "Group", value: .group)],
            selection: $scopeVM.boardScope
          )
          .padding(.horizontal)

          if scopeVM.boardScope == .group && scopeVM.myGroups.count > 1 {
            PillToggle(
              options: scopeVM.myGroups.map { (label: $0.name, value: $0.slug) },
              selection: Binding(
                get: { scopeVM.selectedGroupSlug ?? scopeVM.myGroups[0].slug },
                set: { scopeVM.selectedGroupSlug = $0 }
              ),
              scrollable: true
            )
            .padding(.horizontal)
          }
        }

        Picker("Mode", selection: $selection) {
          Text("Weekly").tag(0)
          Text("Season").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)

        if selection == 0 {
          WeeklyLeaderboardView(sport: scopeVM.sport, groupSlug: activeGroupSlug)
        } else {
          SeasonLeaderboardView(sport: scopeVM.sport, groupSlug: activeGroupSlug)
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
      .task {
        if let client {
          scopeVM.configure(client: client)
          await scopeVM.loadGroups()
        }
      }
    }
    .tint(BoldTheme.Colors.gold)
  }
}
