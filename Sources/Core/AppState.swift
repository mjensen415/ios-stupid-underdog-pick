import Foundation
import SwiftUI
import Supabase

@MainActor
final class AppState: ObservableObject {
  @Published var client: SupabaseClient?
  @Published var session: Session?
  @Published var startupError: Error?
  /// Set by DeepLinkHandler when a /groups/join/:token link (universal or
  /// custom-scheme) is opened. Consumed by RootView's full-screen cover,
  /// which works regardless of whether the user is signed in yet.
  @Published var pendingGroupJoinToken: String?
  /// Set by HomeView's card CTAs to request MainTabView switch to a given
  /// tab index (e.g. "Make Your Pick" -> Games tab). MainTabView consumes
  /// and resets it -- same request/consume pattern as pendingGroupJoinToken.
  @Published var requestedTab: Int?
  /// Set alongside requestedTab when Home's CTA is tapped, so the Games tab
  /// lands on whichever sport was selected on Home instead of always
  /// resetting to CFB. GamesView consumes and resets it, same pattern.
  @Published var requestedSport: String?

  /// Which contest the user last chose via the "Switch Game" sheet (or a
  /// Home/Games entry point that implies one) -- CFB Underdog, Pro Ball
  /// Underdog, and Pickems are separate contests with separate groups, so
  /// Groups needs to know which one is "current" to show the right list,
  /// and to keep showing it if the user leaves and comes back. Persisted
  /// (not just a one-shot request/consume flag like requestedTab) since
  /// Groups can be visited long after the switch happened.
  @Published var currentGame: CurrentGame = .cfb

  /// Set once per session by RootView's launch check (app_version_config)
  /// when the App Store has a newer build than this one. Nil means either
  /// no check has completed yet or the app is current -- UpdateBanner
  /// treats both the same (don't show).
  @Published var updateAvailable: AppVersionConfig?

  /// Route to whichever Underdog Pick sport, updating currentGame so Groups
  /// reflects it. Single place every CFB/Pro Ball entry point should funnel
  /// through instead of setting requestedSport/requestedTab directly.
  func goToUnderdog(sport: String, tab: Int = 1) {
    currentGame = sport == "nfl" ? .nfl : .cfb
    requestedSport = sport
    requestedTab = tab
  }

  /// Route to Pickems, updating currentGame so Groups reflects it, and
  /// requesting the Games tab -- MainTabView's Games slot now renders
  /// PickemsView whenever currentGame is .pickems, the same way it renders
  /// GamesView for .cfb/.nfl, so this is the single place every Pickems
  /// entry point should funnel through instead of juggling a separate
  /// push flag. Harmless no-op if already on the Games tab.
  func goToPickems() {
    currentGame = .pickems
    requestedTab = 1
  }
}

enum CurrentGame: String {
  case cfb
  case nfl
  case pickems
}

private struct SupabaseClientKey: EnvironmentKey {
  static var defaultValue: SupabaseClient? = nil
}
extension EnvironmentValues {
  var supabaseClient: SupabaseClient? {
    get { self[SupabaseClientKey.self] }
    set { self[SupabaseClientKey.self] = newValue }
  }
}

