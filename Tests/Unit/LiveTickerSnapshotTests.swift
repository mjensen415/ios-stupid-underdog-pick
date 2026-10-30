import XCTest
import SwiftUI
@testable import Stupid_Underdog_Pick

/// The live ticker with mock live games (nothing may be live while QA
/// runs). Writes PNGs to $SUP_QA_DIR when set.
@MainActor
final class LiveTickerSnapshotTests: XCTestCase {
  private var mock: [LiveTickerItem] {
    [
      .make(id: UUID(), sport: .cfb, week: 9, home: "Texas Tech", away: "Arizona", homeScore: 10, awayScore: 14, spread: -3),
      .make(id: UUID(), sport: .nfl, week: 8, home: "Detroit", away: "Minnesota", homeScore: 21, awayScore: 17, spread: -3),
      .make(id: UUID(), sport: .cfb, week: 9, home: "Delaware State", away: "Norfolk State", homeScore: 7, awayScore: 3, spread: nil),
      .make(id: UUID(), sport: .nhl, week: nil, home: "Boston", away: "Ottawa", homeScore: 1, awayScore: 2,
            spread: nil, homeMl: -150, awayMl: 130, detail: "2nd"),
    ]
  }

  func testTickerStates() async throws {
    // Sorted like the model does: dogs ahead first.
    let items = mock.sorted { $0.dogLeads && !$1.dogLeads }
    let view = VStack(alignment: .leading, spacing: 20) {
      Text("Marquee (dogs ahead get the red dot + bold)").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
      LiveTickerBar(items: items) { _ in }
      Text("Reduce Motion: static row, scrolls sideways").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
      LiveTickerBar(items: items, forceStatic: true) { _ in }
      ForEach(items) { Text(verbatim: "• " + $0.text + ($0.dogLeads ? "  (dog leads)" : "")).font(BoldTheme.Fonts.body(13)) }
      Spacer()
    }
    .padding(16).padding(.top, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(BoldTheme.Colors.bgPage)

    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.screen.bounds
    window.rootViewController = UIHostingController(rootView: view.preferredColorScheme(.light))
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(nanoseconds: 2_000_000_000)
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = "live-ticker"
    attachment.lifetime = .keepAlways
    add(attachment)
    if let dir = ProcessInfo.processInfo.environment["SUP_QA_DIR"], let png = image.pngData() {
      try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("01-live-ticker-mock.png"))
    }
  }

  func testItemText() {
    let up = LiveTickerItem.make(id: UUID(), sport: .cfb, week: 9, home: "Texas Tech", away: "Arizona",
                                 homeScore: 10, awayScore: 14, spread: -3)
    XCTAssertEqual(up.text, "Arizona +3 14 · Texas Tech 10")
    XCTAssertTrue(up.dogLeads)
    let noLine = LiveTickerItem.make(id: UUID(), sport: .cfb, week: 9, home: "Delaware State", away: "Navy",
                                     homeScore: 7, awayScore: 3, spread: nil)
    XCTAssertEqual(noLine.text, "Navy 3 @ Delaware St 7")
    XCTAssertFalse(noLine.dogLeads)
  }
}
