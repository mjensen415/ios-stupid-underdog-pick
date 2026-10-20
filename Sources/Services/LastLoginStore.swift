import Foundation
import Supabase

/// Which sign-in method this device used last, so AuthView can tag it
/// "LAST USED" and returning players don't make a second account with a
/// different method. Mirrors the web's src/lib/lastLogin.ts (PR #47).
/// Stored per device in UserDefaults; nothing is sent anywhere.
enum LoginMethod: String {
  case google, apple, email
}

enum LastLoginStore {
  private static let key = "sup.lastLoginMethod"

  /// The identity with the newest last_sign_in_at is the method just used.
  /// appMetadata["provider"] is only the *first* provider the account ever
  /// signed up with, so it's the fallback, not the answer. Magic links count
  /// as "email" -- same as the web, since they're the email identity.
  static func method(from user: User) -> LoginMethod? {
    let newest = (user.identities ?? []).max { a, b in
      (a.lastSignInAt ?? .distantPast) < (b.lastSignInAt ?? .distantPast)
    }
    let provider = newest?.provider ?? user.appMetadata["provider"]?.stringValue
    return provider.flatMap(LoginMethod.init(rawValue:))
  }

  /// Call after every successful sign-in (not on session restore -- that
  /// isn't a choice the player made, same as web recording only SIGNED_IN).
  static func remember(user: User) {
    guard let m = method(from: user) else { return }
    UserDefaults.standard.set(m.rawValue, forKey: key)
  }

  static func lastMethod() -> LoginMethod? {
    UserDefaults.standard.string(forKey: key).flatMap(LoginMethod.init(rawValue:))
  }
}
