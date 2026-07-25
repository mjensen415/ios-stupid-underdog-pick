import UIKit

extension Notification.Name {
  static let apnsDeviceTokenReceived = Notification.Name("apnsDeviceTokenReceived")
}

// The app has no AppDelegate.swift elsewhere -- pure SwiftUI App lifecycle --
// so this exists solely to bridge the one UIKit-only callback SwiftUI has no
// equivalent for: receiving the raw APNs device token. Hooked into
// StupidUnderdogApp via @UIApplicationDelegateAdaptor. Posts a notification
// rather than uploading the token directly because this class has no access
// to the authenticated Supabase client -- StupidUnderdogApp observes and
// does the actual upload once appState.client/session exist.
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    NotificationCenter.default.post(name: .apnsDeviceTokenReceived, object: nil, userInfo: ["token": hexToken])
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    #if DEBUG
    print("[Push] didFailToRegisterForRemoteNotifications:", error.localizedDescription)
    #endif
  }
}
