import Foundation
import Supabase

struct AuthService {
  let client: SupabaseClient

  enum AuthError: LocalizedError {
    case noClient
    case noSessionReturned
    var errorDescription: String? {
      switch self {
      case .noClient: return "Auth client unavailable."
      case .noSessionReturned: return "Sign-in didn’t return a session."
      }
    }
  }

  // MARK: - Email/Password
  @MainActor
  @discardableResult
  func signIn(email: String, password: String) async throws -> Session {
    #if DEBUG
    print("[Auth][Email] attempting sign-in for:", email)
    #endif
    _ = try await client.auth.signIn(email: email, password: password)
    // Fetch current session after sign-in
    let session = try await client.auth.session
    #if DEBUG
    print("[Auth][Email] session ok. user:", session.user.id.uuidString)
    #endif
    return session
  }

  @MainActor
  func signUp(email: String, password: String) async throws {
    _ = try await client.auth.signUp(email: email, password: password)
  }

  @MainActor
  func signOut() async {
    do { try await client.auth.signOut() } catch {
      #if DEBUG
      print("[Auth][SignOut][ERR]", error.localizedDescription)
      #endif
    }
  }

  // MARK: - Magic Link / OAuth
  @MainActor
  func sendMagicLink(to email: String, redirectTo: URL?) async throws {
    _ = try await client.auth.signInWithOTP(email: email, redirectTo: redirectTo)
  }

  /// Google OAuth (requires Supabase redirect URL: sup://underdog)
  @MainActor
  @discardableResult
  func signInWithGoogle(redirect: URL) async throws -> Session {
    #if DEBUG
    print("[Auth][Google] starting OAuth with redirect:", redirect.absoluteString)
    #endif

    try await client.auth.signInWithOAuth(
      provider: .google,
      redirectTo: redirect
    )

    // After ASWebAuthenticationSession returns to app via .onOpenURL,
    // poll briefly for the session to become available.
    for attempt in 0..<20 {
      if let s = try? await client.auth.session {
        #if DEBUG
        print("[Auth][Google] session ok after callback. attempts:", attempt)
        #endif
        return s
      }
      try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }

    #if DEBUG
    print("[Auth][Google][ERR] no session after OAuth callback.")
    #endif
    throw AuthError.noSessionReturned
  }

  /// Apple OAuth (requires Supabase redirect URL: sup://underdog). Same
  /// ASWebAuthenticationSession flow as Google -- Supabase's Apple provider
  /// is already configured with the Services ID, so no native
  /// AuthenticationServices/SIWA button is needed here.
  @MainActor
  @discardableResult
  func signInWithApple(redirect: URL) async throws -> Session {
    #if DEBUG
    print("[Auth][Apple] starting OAuth with redirect:", redirect.absoluteString)
    #endif

    try await client.auth.signInWithOAuth(
      provider: .apple,
      redirectTo: redirect
    )

    for attempt in 0..<20 {
      if let s = try? await client.auth.session {
        #if DEBUG
        print("[Auth][Apple] session ok after callback. attempts:", attempt)
        #endif
        return s
      }
      try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }

    #if DEBUG
    print("[Auth][Apple][ERR] no session after OAuth callback.")
    #endif
    throw AuthError.noSessionReturned
  }
}

