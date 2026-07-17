import SwiftUI

struct RootView: View {
  @EnvironmentObject var appState: AppState

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
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView().environmentObject(AppState())
  }
}

