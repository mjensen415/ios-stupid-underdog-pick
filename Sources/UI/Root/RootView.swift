import SwiftUI

struct RootView: View {
  @EnvironmentObject var appState: AppState
  @State private var showOnboarding = false

  var body: some View {
    Group {
      if appState.session == nil {
        AuthView()
      } else {
        MainTabView()
      }
    }
    .fullScreenCover(isPresented: Binding(
      get: { appState.pendingGroupJoinToken != nil },
      set: { isPresented in if !isPresented { appState.pendingGroupJoinToken = nil } }
    )) {
      if let token = appState.pendingGroupJoinToken {
        GroupJoinByTokenView(token: token)
      }
    }
    .fullScreenCover(isPresented: $showOnboarding) {
      if let client = appState.client {
        OnboardingFlowView(client: client, isPresented: $showOnboarding)
      }
    }
    // Runs once per session appearing (login/logout, not every relaunch
    // with an existing session already restored -- .task(id:) only
    // re-fires when the id itself changes).
    .task(id: appState.session?.user.id) {
      guard let client = appState.client, appState.session != nil else { return }
      let profile = try? await ProfilesService(client: client).fetchMyProfile()
      showOnboarding = profile?.has_onboarded == false
    }
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView().environmentObject(AppState())
  }
}

