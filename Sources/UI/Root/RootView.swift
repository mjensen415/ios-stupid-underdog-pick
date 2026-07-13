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
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView().environmentObject(AppState())
  }
}

