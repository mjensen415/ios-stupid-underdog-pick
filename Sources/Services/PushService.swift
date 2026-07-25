import Foundation
import UIKit
import UserNotifications
import Supabase

struct NotificationPreferencesRow: Codable, Equatable {
  var pick_reminder: Bool
  var game_live: Bool
  var game_result: Bool
  var weekly_recap: Bool

  static let allEnabled = NotificationPreferencesRow(pick_reminder: true, game_live: true, game_result: true, weekly_recap: true)
}

struct PushService {
  let client: SupabaseClient

  /// Asks iOS for notification permission and, if granted, tells
  /// UIApplication to register for a device token -- the token itself
  /// arrives asynchronously via AppDelegate.didRegisterForRemoteNotifications,
  /// not returned here.
  @MainActor
  func requestPermission() async -> Bool {
    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    if granted {
      UIApplication.shared.registerForRemoteNotifications()
    }
    return granted
  }

  @MainActor
  func currentAuthorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  /// Upserts the APNs device token so send-push can find it. onConflict
  /// matches the (user_id, token) unique constraint -- reinstalling or
  /// re-registering on the same device is a no-op, not a duplicate row.
  func registerDeviceToken(_ token: String) async throws {
    struct Row: Encodable { let user_id: UUID; let token: String; let platform: String }
    let userId = try await client.auth.session.user.id
    _ = try await client
      .from("device_tokens")
      .upsert(Row(user_id: userId, token: token, platform: "ios"), onConflict: "user_id,token")
      .execute()
  }

  func fetchPreferences() async throws -> NotificationPreferencesRow {
    let userId = try await client.auth.session.user.id
    let res = try await client
      .from("notification_preferences")
      .select("pick_reminder, game_live, game_result, weekly_recap")
      .eq("user_id", value: userId)
      .limit(1)
      .execute()
    let rows = try JSONDecoder().decode([NotificationPreferencesRow].self, from: res.data)
    return rows.first ?? .allEnabled
  }

  func updatePreferences(_ prefs: NotificationPreferencesRow) async throws {
    struct Upsert: Encodable {
      let user_id: UUID
      let pick_reminder: Bool
      let game_live: Bool
      let game_result: Bool
      let weekly_recap: Bool
    }
    let userId = try await client.auth.session.user.id
    _ = try await client
      .from("notification_preferences")
      .upsert(
        Upsert(user_id: userId, pick_reminder: prefs.pick_reminder, game_live: prefs.game_live, game_result: prefs.game_result, weekly_recap: prefs.weekly_recap),
        onConflict: "user_id"
      )
      .execute()
  }
}
