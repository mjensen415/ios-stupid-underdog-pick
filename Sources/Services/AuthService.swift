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

  // MARK: - Password reset
  /// Emails a reset link that lands on the website's /set-new-password page
  /// (same redirect as the web's Auth.tsx), where the new password is set.
  ///
  /// Deliberately bypasses client.auth.resetPasswordForEmail: this client
  /// uses PKCE (supabase-swift's default), which would put a ?code= link in
  /// the email whose code verifier only exists on this phone -- the web page
  /// can't redeem it. The web client uses the implicit flow (tokens in the
  /// URL hash, which SetNewPassword picks up), so send the same request the
  /// web sends: POST /auth/v1/recover with no code_challenge.
  ///
  /// Supabase answers 200 whether or not the email has an account (no
  /// account enumeration). Its built-in sender allows ~3 emails/hour for the
  /// whole project, so a 429 here is expected now and then.
  func sendPasswordReset(email: String) async throws {
    guard let config = SupabaseClientProvider.projectConfig() else { throw AuthError.noClient }
    var components = URLComponents(
      url: config.url.appendingPathComponent("auth/v1/recover"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [URLQueryItem(name: "redirect_to", value: SiteLinks.setNewPassword.absoluteString)]
    guard let url = components?.url else { throw URLError(.badURL) }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(["email": email])

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      struct GoTrueError: Decodable { let msg: String?; let message: String?; let error_description: String? }
      let body = try? JSONDecoder().decode(GoTrueError.self, from: data)
      throw PasswordResetError(
        status: status,
        message: body?.msg ?? body?.message ?? body?.error_description ?? "Request failed (\(status))."
      )
    }
  }

  struct PasswordResetError: LocalizedError {
    let status: Int
    let message: String
    var isRateLimited: Bool { status == 429 }
    var errorDescription: String? { message }
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

