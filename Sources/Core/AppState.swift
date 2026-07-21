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

