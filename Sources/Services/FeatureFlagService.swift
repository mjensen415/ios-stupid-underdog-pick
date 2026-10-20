import Foundation
import SwiftUI
import Supabase

// Growth/monetization features ship switched off behind public.feature_flags
// (key, enabled), flipped by admins from the web's Admin -> Growth tab with
// no app release needed. Anyone can read the table (anon and authenticated).
// Mirrors the web's src/hooks/useFlag.ts + useAdmin: a flag counts as on for
// a feature when `useFlag(key) || isAdmin`, so admins see gated features
// before everyone else.

/// Flag keys as they exist in public.feature_flags. Plain strings in the
/// table, so a typo here would silently read as "off" -- keep them in one place.
enum FeatureFlagKey {
  static let supPro = "sup_pro"
  static let supProOpen = "sup_pro_open"
  static let hoops = "hoops"
  static let pucks = "pucks"
  static let watchLinks = "watch_links"
  static let trackRecord = "track_record"
  static let lineAlerts = "line_alerts"
}

struct FeatureFlagService {
  let client: SupabaseClient

  private struct FlagRow: Decodable {
    let key: String
    let enabled: Bool
  }

  func fetchFlags() async throws -> [String: Bool] {
    let res = try await client.from("feature_flags").select("key, enabled").execute()
    let rows = try JSONDecoder().decode([FlagRow].self, from: res.data)
    return Dictionary(rows.map { ($0.key, $0.enabled) }, uniquingKeysWith: { _, last in last })
  }

  /// Same check as the web's useAdmin: a row in public.admins for this user.
  /// RLS only lets admins read that table, so a non-admin just gets no rows.
  /// Nil means the check itself failed (network), not "not an admin".
  func fetchIsAdmin(userId: UUID) async -> Bool? {
    struct AdminRow: Decodable { let id: UUID }
    guard let res = try? await client.from("admins").select("id").eq("user_id", value: userId).limit(1).execute(),
          let rows = try? JSONDecoder().decode([AdminRow].self, from: res.data)
    else { return nil }
    return !rows.isEmpty
  }
}

/// App-wide cached flags, injected as an environment object by
/// StupidUnderdogApp and refreshed by RootView on sign-in and on foreground.
/// Views read `isVisible(_:)` for gated features (flag on, or admin).
@MainActor
final class FeatureFlagStore: ObservableObject {
  @Published private(set) var flags: [String: Bool] = [:]
  @Published private(set) var isAdmin = false

  /// Same 5-minute staleTime as the web's react-query cache: flags change
  /// rarely, and a foreground refresh shouldn't hit the table every time.
  static let cacheTTL: TimeInterval = 5 * 60
  private var fetchedAt: Date?
  private var adminCheckedFor: UUID?
  /// The in-flight fetch, shared by every caller. Launch fires several
  /// refreshes at once (session restore, foreground), so they join one fetch
  /// instead of each hitting the table. Unstructured on purpose: RootView's
  /// .task(id:) is cancelled the moment the saved session restores, and a
  /// fetch tied to that task would be cancelled with it.
  private var flagsTask: Task<Void, Never>?

  /// The raw flag, like the web's useFlag: true only once loaded and on --
  /// off while loading or if the fetch failed.
  func isOn(_ key: String) -> Bool { flags[key] == true }

  /// `useFlag(key) || isAdmin` -- what gated UI should check.
  func isVisible(_ key: String) -> Bool { isAdmin || isOn(key) }

  func refresh(client: SupabaseClient, userId: UUID?, force: Bool = false) async {
    let service = FeatureFlagService(client: client)

    let stale = fetchedAt.map { Date().timeIntervalSince($0) > Self.cacheTTL } ?? true
    if force || stale {
      if flagsTask == nil {
        flagsTask = Task { [weak self] in
          // On failure keep the last good set rather than flipping features
          // off mid-session over one network blip.
          let fresh = try? await service.fetchFlags()
          guard let self else { return }
          if let fresh {
            self.flags = fresh
            self.fetchedAt = Date()
            #if DEBUG
            print("[Flags] loaded:", fresh.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            #endif
          }
          self.flagsTask = nil
        }
      }
      await flagsTask?.value
    }

    // Admin status only changes with the signed-in user, so check it once
    // per user rather than on every refresh.
    guard let userId else {
      isAdmin = false
      adminCheckedFor = nil
      return
    }
    // The cancellation check drops a result that arrives after the user
    // changed (RootView cancels this task on sign-in/out).
    if force || adminCheckedFor != userId, let admin = await service.fetchIsAdmin(userId: userId), !Task.isCancelled {
      isAdmin = admin
      adminCheckedFor = userId
      #if DEBUG
      print("[Flags] isAdmin:", admin)
      #endif
    }
  }
}
