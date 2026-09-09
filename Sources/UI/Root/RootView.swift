import SwiftUI
import UIKit

struct RootView: View {
  @EnvironmentObject var appState: AppState
  @State private var showOnboarding = false

  // Covers a gap the universal-link handling can't: someone taps an invite
  // link with the app not yet installed, goes to download it separately,
  // and creates a fresh account with no memory of the invite at all --
  // DeepLinkHandler never runs since no URL was ever handed to this app in
  // that flow, unlike the case in-app + already-installed already handles
  // via appState.pendingGroupJoinToken. If the invite web page copies its
  // own URL to the clipboard before sending someone to the App Store (or
  // the person just copied the link themselves to paste into the app),
  // this picks it up the one time it matters -- right as a brand-new
  // account reaches onboarding -- instead of checking on every cold
  // launch, which would otherwise show iOS's "Allow Paste" prompt for
  // completely unrelated clipboard contents on every single app open.
  private func checkPasteboardForPendingInvite() {
    guard appState.pendingGroupJoinToken == nil,
          let text = UIPasteboard.general.string,
          let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let token = DeepLinkHandler.groupJoinToken(from: url)
    else { return }
    appState.pendingGroupJoinToken = token
  }

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
      checkPasteboardForPendingInvite()
      // Don't show onboarding in the same tick as a pending invite join --
      // two simultaneous fullScreenCovers on one view isn't reliable in
      // SwiftUI. Let the invite cover show uncontested; the onChange below
      // picks up onboarding once it's dismissed.
      guard appState.pendingGroupJoinToken == nil else { return }
      let profile = try? await ProfilesService(client: client).fetchMyProfile()
      showOnboarding = profile?.has_onboarded == false
    }
    .onChange(of: appState.pendingGroupJoinToken) { _, newToken in
      guard newToken == nil, let client = appState.client, appState.session != nil else { return }
      Task {
        let profile = try? await ProfilesService(client: client).fetchMyProfile()
        showOnboarding = profile?.has_onboarded == false
      }
    }
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView().environmentObject(AppState())
  }
}

