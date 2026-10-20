import Foundation
import SwiftUI
import Supabase

// SUP Pro, free tier only. Pro is info tools only and never affects entry,
// scoring, picks or prizes. App Store rules for this app: no prices, no
// purchase or upgrade buttons, no links to buy on the web, no "$" anywhere
// about Pro. Access comes only from what the server already grants:
// has_sup_pro() (admin comps, the free opt-in, sup_pro_open) -- iOS never
// sells or unlocks anything itself.

struct ProOptinStatus: Decodable, Equatable {
  let eligible: Bool
  let claimed: Bool
  /// When the free season ends (ISO timestamp), nil when not claimed.
  let until: String?

  static let none = ProOptinStatus(eligible: false, claimed: false, until: nil)

  var untilDate: Date? {
    guard let until else { return nil }
    return ISO8601DateFormatter().date(from: until)
      ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: until) }()
      ?? { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(until.prefix(10))) }()
  }

  /// "Feb 15, 2027", or the web's fallback wording.
  var untilText: String {
    guard let d = untilDate else { return "the end of the season" }
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    // A calendar end date stored as UTC midnight: show that day everywhere.
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: d)
  }
}

struct ProService {
  let client: SupabaseClient

  /// Fail closed: any error means "not Pro".
  func hasSupPro(userId: UUID) async -> Bool {
    struct P: Encodable { let p_user: UUID }
    guard let res = try? await client.rpc("has_sup_pro", params: P(p_user: userId)).execute() else { return false }
    return (try? JSONDecoder().decode(Bool.self, from: res.data)) == true
  }

  func optinStatus() async -> ProOptinStatus {
    guard let res = try? await client.rpc("pro_optin_status").execute(),
          let s = try? JSONDecoder().decode(ProOptinStatus.self, from: res.data)
    else { return .none }
    return s
  }

  /// Turns the free opt-in on (claim) or off (release). Only ever called from
  /// the player's own tap on the opt-in card.
  func setOptin(_ on: Bool) async throws -> ProOptinStatus {
    let res = try await client.rpc(on ? "pro_optin_claim" : "pro_optin_release").execute()
    return try JSONDecoder().decode(ProOptinStatus.self, from: res.data)
  }
}

/// App-wide Pro state, injected next to FeatureFlagStore and refreshed by
/// RootView on sign-in and foreground.
@MainActor
final class ProStore: ObservableObject {
  @Published private(set) var hasPro = false
  @Published private(set) var optin: ProOptinStatus = .none
  @Published private(set) var loaded = false
  @Published var changing = false
  @Published var changeError: String?

  /// Admins count as Pro (web usePro: isAdmin || has_sup_pro).
  func isPro(admin: Bool) -> Bool { admin || hasPro }

  /// Where the Pro screen's entry points show: the launch flag, Pro members
  /// (admins included) and players eligible for the free opt-in.
  func showEntry(flags: FeatureFlagStore) -> Bool {
    flags.isVisible(FeatureFlagKey.supPro) || isPro(admin: flags.isAdmin) || optin.eligible
  }

  func refresh(client: SupabaseClient, userId: UUID?) async {
    guard let userId else {
      hasPro = false; optin = .none; loaded = false
      return
    }
    let svc = ProService(client: client)
    async let pro = svc.hasSupPro(userId: userId)
    async let status = svc.optinStatus()
    let (p, s) = await (pro, status)
    guard !Task.isCancelled else { return }
    hasPro = p
    optin = s
    loaded = true
  }

  func setOptin(_ on: Bool, client: SupabaseClient, userId: UUID) async {
    changing = true; changeError = nil
    defer { changing = false }
    do {
      optin = try await ProService(client: client).setOptin(on)
      hasPro = await ProService(client: client).hasSupPro(userId: userId)
    } catch {
      changeError = "That didn't work. Try again in a minute."
    }
  }

  #if DEBUG
  /// Test-only: inject state for snapshot tests. Never used by the app.
  func _setForTesting(hasPro: Bool, optin: ProOptinStatus) {
    self.hasPro = hasPro
    self.optin = optin
    self.loaded = true
  }
  #endif
}

// MARK: - Where to watch (game_broadcasts) and Last 3 (recent form)

struct ProDataService {
  let client: SupabaseClient

  /// Networks by ESPN event id. Public table; empty on any error.
  func broadcasts(eventIds: [String]) async -> [String: [BroadcastNetwork]] {
    let ids = Array(Set(eventIds.filter { !$0.isEmpty })).sorted()
    guard !ids.isEmpty else { return [:] }
    struct Row: Decodable { let espn_event_id: String; let networks: [BroadcastNetwork]? }
    var out: [String: [BroadcastNetwork]] = [:]
    // Chunked so a big CFB week doesn't build an oversized URL.
    for chunk in stride(from: 0, to: ids.count, by: 120).map({ Array(ids[$0..<min($0 + 120, ids.count)]) }) {
      guard let res = try? await client.from("game_broadcasts").select("espn_event_id, networks").in("espn_event_id", values: chunk).execute(),
            let rows = try? JSONDecoder().decode([Row].self, from: res.data) else { continue }
      for r in rows { out[r.espn_event_id] = r.networks ?? [] }
    }
    return out
  }

  /// ESPN event ids for CFB / Pro Ball games: games.cfbd_game_id for CFB,
  /// games.espn_game_id for Pro Ball (v_games_named doesn't carry espn_game_id).
  func espnIds(gameIds: [UUID], sport: String) async -> [UUID: String] {
    guard !gameIds.isEmpty else { return [:] }
    struct Row: Decodable { let id: UUID; let espn_game_id: Int64?; let cfbd_game_id: Int64? }
    guard let res = try? await client.from("games").select("id, espn_game_id, cfbd_game_id").in("id", values: gameIds).execute(),
          let rows = try? JSONDecoder().decode([Row].self, from: res.data) else { return [:] }
    var out: [UUID: String] = [:]
    for r in rows {
      let espn = sport == "nfl" ? (r.espn_game_id ?? r.cfbd_game_id) : (r.cfbd_game_id ?? r.espn_game_id)
      if let espn { out[r.id] = String(espn) }
    }
    return out
  }

  /// A team's last `n` finished CFB / Pro Ball games before `before`, from its
  /// own side. Reads v_games_named (city-only names, same as the game list),
  /// matching on team id, or the name when the id is missing.
  func recentForm(sport: String, teamId: UUID?, teamName: String?, before: Date, n: Int = 3) async -> [FormGame] {
    var ors: [String] = []
    if let teamId { ors += ["home_team_id.eq.\(teamId.uuidString.lowercased())", "away_team_id.eq.\(teamId.uuidString.lowercased())"] }
    if teamId == nil, let teamName {
      let q = "\"\(teamName.replacingOccurrences(of: "\"", with: "\\\""))\""
      ors += ["home_name.eq.\(q)", "away_name.eq.\(q)"]
    }
    guard !ors.isEmpty else { return [] }
    struct Row: Decodable {
      let home_name: String?; let away_name: String?
      let home_team_id: UUID?; let away_team_id: UUID?
      let home_points: Int?; let away_points: Int?
      let closing_spread: Double?; let latest_spread: Double?
      let start_time: Date
    }
    let iso = ISO8601DateFormatter().string(from: before)
    guard let res = try? await client.from("v_games_named")
      .select("home_name, away_name, home_team_id, away_team_id, home_points, away_points, closing_spread, latest_spread, start_time")
      .eq("sport", value: sport).eq("status", value: "final").lt("start_time", value: iso)
      .or(ors.joined(separator: ","))
      .order("start_time", ascending: false).limit(n + 2)
      .execute()
    else { return [] }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withFallback
    guard let rows = try? dec.decode([Row].self, from: res.data) else { return [] }
    let key = teamId?.uuidString.lowercased()
    return rows.compactMap { g in
      RecentForm.toFormGame(RawFinal(
        home: g.home_name ?? "", away: g.away_name ?? "",
        homeKey: g.home_team_id?.uuidString.lowercased(), awayKey: g.away_team_id?.uuidString.lowercased(),
        homePts: g.home_points, awayPts: g.away_points,
        spread: g.closing_spread ?? g.latest_spread, startTime: g.start_time
      ), key: key, name: teamId == nil ? teamName : nil)
    }.prefix(n).map { $0 }
  }
}
