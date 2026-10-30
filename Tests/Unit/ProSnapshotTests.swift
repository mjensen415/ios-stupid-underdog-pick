import XCTest
import SwiftUI
import Supabase
@testable import Stupid_Underdog_Pick

/// Renders the Pro-only UI with injected Pro state (never by claiming Pro
/// for a real account) and saves PNGs for QA. Game, form and broadcast data
/// are real, read-only reads of public tables.
///
/// Writes to $SUP_QA_DIR when set (TEST_RUNNER_SUP_QA_DIR=... on xcodebuild).
@MainActor
final class ProSnapshotTests: XCTestCase {
  func testProOptinCard() async throws {
    let pro = ProStore()
    pro._setForTesting(hasPro: false, optin: ProOptinStatus(eligible: true, claimed: false, until: "2027-02-15T00:00:00+00:00"))
    try await snapshot(NavigationStack { ProView() }, pro: pro, name: "pro-01-optin-card")
  }

  func testProTeaserForNonEligible() async throws {
    let pro = ProStore()
    pro._setForTesting(hasPro: false, optin: .none)
    try await snapshot(NavigationStack { ProView() }, pro: pro, name: "pro-02-teaser")
  }

  func testProMemberHub() async throws {
    let pro = ProStore()
    pro._setForTesting(hasPro: true, optin: ProOptinStatus(eligible: true, claimed: true, until: "2027-02-15T00:00:00+00:00"))
    try await snapshot(NavigationStack { ProView() }, pro: pro, name: "pro-03-member-hub")
  }

  func testProUnderdogBoard() async throws {
    let pro = ProStore()
    pro._setForTesting(hasPro: true, optin: .none)
    try await snapshot(NavigationStack { UnderdogBoardView() }, pro: pro, name: "pro-04-underdog-board", wait: 4)
  }

  func testTrackRecord() async throws {
    try await snapshot(NavigationStack { TrackRecordView() }, pro: ProStore(), name: "pro-05-track-record", wait: 4)
  }

  /// The pick card for a real upcoming lined CFB game, as a Pro member
  /// sees it: LAST 3 boxes and watch chips.
  func testPickCardAsPro() async throws {
    let client = try SupabaseClientProvider.makeClient()
    let g = try await upcomingGame(client: client)
    let data = ProDataService(client: client)
    let ids = await data.espnIds(gameIds: [g.id], sport: g.sport)
    let nets = await data.broadcasts(eventIds: Array(ids.values))
    let links = ids[g.id].flatMap { eid in nets[eid].map { WatchLinks.links(sport: .cfb, eventId: eid, networks: $0) } } ?? []
    let logoMap = await logos(client: client)
    let pro = ProStore()
    pro._setForTesting(hasPro: true, optin: .none)
    let sheet = Color.clear.sheet(isPresented: .constant(true)) {
      PickCardSheet(game: g, logoFor: { $0.flatMap { logoMap[$0] } }, isCurrentPick: false, hasOtherPick: false, isPro: true,
                    watchEnabled: ids[g.id] != nil, watchLinks: links, onLock: { _ in false }, onClear: {})
    }
    try await snapshot(sheet, pro: pro, name: "pro-06-pick-card-pro", wait: 5)
  }

  /// Lock-in re-check: the "spread moved, confirm at +X?" state, for a
  /// real upcoming game with its line nudged 1.5 points (free tier).
  func testPickCardLineMoved() async throws {
    let client = try SupabaseClientProvider.makeClient()
    let g = try await upcomingGame(client: client)
    let logoMap = await logos(client: client)
    let moved = (g.underdogSpread ?? 3) + 1.5
    let sheet = Color.clear.sheet(isPresented: .constant(true)) {
      PickCardSheet(game: g, logoFor: { $0.flatMap { logoMap[$0] } }, isCurrentPick: false, hasOtherPick: false, isPro: false,
                    watchEnabled: false, watchLinks: [], onLock: { _ in false }, onClear: {}, initialMovedSpread: moved)
    }
    try await snapshot(sheet, pro: ProStore(), name: "11-pick-card-line-moved", wait: 4)
  }

  /// Layout A rows with Pro watch capsules, from this week's real games.
  func testGameRowsWithWatchCapsules() async throws {
    let client = try SupabaseClientProvider.makeClient()
    let ctx = try await ContextService(client: client).getCurrentContext(sport: "cfb")
    let games = Array(try await GamesService(client: client).fetch(season: ctx.season, week: ctx.week, sport: "cfb")
      .filter { $0.derivedFavoriteTeamId != nil }.prefix(8))
    let data = ProDataService(client: client)
    let ids = await data.espnIds(gameIds: games.map(\.id), sport: "cfb")
    let nets = await data.broadcasts(eventIds: Array(ids.values))
    let logoMap = await logos(client: client)
    let list = List {
      ForEach(games) { g in
        let link = ids[g.id].flatMap { eid in nets[eid].flatMap { WatchLinks.primary(sport: .cfb, eventId: eid, networks: $0) } }
        GameRowView(game: g, logoFor: { $0.flatMap { logoMap[$0] } }, isSelected: false, isFirstInDay: g.id == games.first?.id,
                    isLastInDay: g.id == games.last?.id, watch: link)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(BoldTheme.Colors.bgPage)
    try await snapshot(list, pro: ProStore(), name: "pro-07-rows-watch-capsules", wait: 3)
  }

  // MARK: Helpers

  private func logos(client: SupabaseClient) async -> [UUID: URL] {
    struct T: Decodable { let id: UUID; let logo_url: String? }
    guard let res = try? await client.from("teams").select("id, logo_url").execute(),
          let rows = try? JSONDecoder().decode([T].self, from: res.data) else { return [:] }
    return Dictionary(rows.compactMap { t in t.logo_url.flatMap(URL.init(string:)).map { (t.id, $0) } }, uniquingKeysWith: { a, _ in a })
  }

  private func upcomingGame(client: SupabaseClient) async throws -> Game {
    let ctx = try await ContextService(client: client).getCurrentContext(sport: "cfb")
    let games = try await GamesService(client: client).fetch(season: ctx.season, week: ctx.week, sport: "cfb")
    let open = games.filter { $0.derivedFavoriteTeamId != nil && $0.startTime > Date() }
    return try XCTUnwrap(open.first(where: { ($0.underdogSpread ?? 0) >= 3 }) ?? open.first ?? games.first)
  }

  private func snapshot<V: View>(_ view: V, pro: ProStore, name: String, wait: Double = 2) async throws {
    let client = try SupabaseClientProvider.makeClient()
    let root = view
      .environmentObject(AppState())
      .environmentObject(FeatureFlagStore())
      .environmentObject(pro)
      .environment(\.supabaseClient, client)
      .preferredColorScheme(.light)

    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.screen.bounds
    window.rootViewController = UIHostingController(rootView: root)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))

    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)

    if let dir = ProcessInfo.processInfo.environment["SUP_QA_DIR"], let png = image.pngData() {
      try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
  }
}
