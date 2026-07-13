import Foundation
import SwiftUI
import Supabase

@MainActor
final class AppState: ObservableObject {
  @Published var client: SupabaseClient?
  @Published var session: Session?
  @Published var startupError: Error?
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

