import XCTest
import SwiftUI
@testable import Stupid_Underdog_Pick

/// Home's top (pick block + "Last week:" line) for the result states the
/// simulator account can't reach on demand. Synthetic data, no network.
/// Writes PNGs to $SUP_QA_DIR when set.
@MainActor
final class HomeLastWeekSnapshotTests: XCTestCase {
  private let home = UUID(), away = UUID()

  private func detail(status: String, homePts: Int?, awayPts: Int?) -> HomePickDetail {
    let g = Game(id: UUID(), season: 2026, week: 8, homeTeam: "Texas Tech Red Raiders", awayTeam: "Arizona Wildcats",
                 homeTeamId: home, awayTeamId: away, favoriteTeamId: nil, startTime: Date().addingTimeInterval(-86_400 * 6),
                 bettingLine: nil, latestSpread: -3, picksLocked: true, status: status,
                 homePoints: homePts, awayPoints: awayPts, sport: "cfb", homeShort: "Texas Tech", awayShort: "Arizona")
    let p = Pick(id: UUID(), user_id: UUID(), game_id: g.id, picked_team_id: away, season: 2026, week: 8,
                 created_at: nil, locked_spread: nil)
    return HomePickDetail(pick: p, game: g, logoURL: nil)
  }

  func testLastWeekStates() async throws {
    let view = VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Good morning, Player").font(BoldTheme.Fonts.body(22, weight: .bold))
        Text("Picks lock in 6h 28m").font(BoldTheme.Fonts.body(15)).foregroundColor(BoldTheme.Colors.textDim)
      }
      PickBlock(sport: "CFB", week: 9, status: .cta("Pick now →"), detail: nil, kickoff: Date().addingTimeInterval(3600 * 6)) {}
        .padding(.top, 16)
      ForEach(Array([("final", 24, 27), ("final", 31, 10), ("in_progress", 14, 7)].enumerated()), id: \.offset) { _, s in
        LastWeekLine(detail: self.detail(status: s.0, homePts: s.1, awayPts: s.2)).padding(.top, 12)
      }
      Spacer()
    }
    .padding(16)
    .padding(.top, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(BoldTheme.Colors.bgPage)
    .foregroundColor(BoldTheme.Colors.text)

    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.screen.bounds
    window.rootViewController = UIHostingController(rootView: view.preferredColorScheme(.light))
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(nanoseconds: 1_000_000_000)
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = "home-last-week-states"
    attachment.lifetime = .keepAlways
    add(attachment)
    if let dir = ProcessInfo.processInfo.environment["SUP_QA_DIR"], let png = image.pngData() {
      try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("05-home-last-week-won-lost-in-progress.png"))
    }
  }
}
