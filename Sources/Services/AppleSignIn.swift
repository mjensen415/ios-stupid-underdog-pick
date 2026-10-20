import AuthenticationServices
import CryptoKit
import Foundation
import Supabase
import UIKit

/// Native Sign in with Apple (App Store guideline 4.8 / HIG): the system
/// Apple ID sheet instead of Supabase's web OAuth page. The ID token goes to
/// Supabase via signInWithIdToken; the one-time authorization code goes to
/// the apple-token-exchange edge function so delete-account can revoke the
/// user's Apple tokens later (guideline 5.1.1(v)).
enum AppleNonce {
  /// A random nonce. Apple gets its SHA-256 (in the request); Supabase gets
  /// the raw value and checks it hashes to the token's `nonce` claim, so a
  /// token can't be replayed from another sign-in.
  static func random(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
    var bytes = [UInt8](repeating: 0, count: length)
    if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
      // Never expected; SystemRandomNumberGenerator is also a CSPRNG.
      var rng = SystemRandomNumberGenerator()
      bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &rng) }
    }
    return String(bytes.map { charset[Int($0) % charset.count] })
  }

  static func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/// What a completed Apple authorization hands back that we need.
struct AppleCredential {
  let idToken: String
  let rawNonce: String
  /// Short-lived (~5 min), single use. Exchanged server-side for a refresh token.
  let authorizationCode: String?
  /// Only present the first time this Apple ID authorizes the app.
  let fullName: PersonNameComponents?

  enum Failure: LocalizedError {
    case missingToken
    var errorDescription: String? { "Apple didn't return a sign-in token." }
  }

  init(authorization: ASAuthorization, rawNonce: String) throws {
    guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
          let tokenData = cred.identityToken,
          let token = String(data: tokenData, encoding: .utf8)
    else { throw Failure.missingToken }
    idToken = token
    self.rawNonce = rawNonce
    authorizationCode = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
    fullName = cred.fullName
  }

  /// "Taylor Swift" from the name parts, or nil when Apple sent none.
  var displayName: String? {
    guard let fullName else { return nil }
    let s = PersonNameComponentsFormatter().string(from: fullName).trimmingCharacters(in: .whitespaces)
    return s.isEmpty ? nil : s
  }

  static func isCancel(_ error: Error) -> Bool {
    (error as? ASAuthorizationError)?.code == .canceled
  }
}

/// Configures an Apple ID request the same way for the sign-in button and
/// the delete-account re-confirmation.
func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest, rawNonce: String, scopes: [ASAuthorization.Scope]) {
  request.requestedScopes = scopes
  request.nonce = AppleNonce.sha256(rawNonce)
}

/// Runs an Apple ID authorization without a button -- used only to get a
/// fresh authorization code when deleting an account that has no stored
/// Apple token yet (e.g. it signed in through the old web flow).
@MainActor
final class AppleReauthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private var continuation: CheckedContinuation<ASAuthorization, Error>?
  private var controller: ASAuthorizationController?

  func authorize() async throws -> AppleCredential {
    let nonce = AppleNonce.random()
    let request = ASAuthorizationAppleIDProvider().createRequest()
    configureAppleRequest(request, rawNonce: nonce, scopes: [])
    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.presentationContextProvider = self
    self.controller = controller
    let authorization = try await withCheckedThrowingContinuation { (c: CheckedContinuation<ASAuthorization, Error>) in
      continuation = c
      controller.performRequests()
    }
    return try AppleCredential(authorization: authorization, rawNonce: nonce)
  }

  nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    MainActor.assumeIsolated { finish(.success(authorization)) }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    MainActor.assumeIsolated { finish(.failure(error)) }
  }

  nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
  }

  private func finish(_ result: Result<ASAuthorization, Error>) {
    continuation?.resume(with: result)
    continuation = nil
    controller = nil
  }
}

/// Hands Apple's authorization code to the server so it can be exchanged
/// for a refresh token (stored service-role only) and revoked when the
/// account is deleted. Best effort and silent: if apple-token-exchange
/// isn't deployed or configured yet, sign-in carries on regardless and
/// delete-account asks for a fresh code instead.
enum AppleTokenService {
  static func registerAuthorizationCode(_ code: String, client: SupabaseClient) async {
    struct Body: Encodable { let authorization_code: String }
    struct Ack: Decodable { let success: Bool? }
    do {
      let _: Ack = try await client.functions.invoke(
        "apple-token-exchange",
        options: .init(method: .post, body: Body(authorization_code: code))
      )
    } catch {
      #if DEBUG
      print("[Auth][Apple] token exchange skipped:", error.localizedDescription)
      #endif
    }
  }
}
