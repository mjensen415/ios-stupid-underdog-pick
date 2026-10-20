import XCTest
@testable import Stupid_Underdog_Pick

final class LineRecheckTests: XCTestCase {
  func testUnchangedLine() {
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: -7, currentHomeSpread: -7), .unchanged)
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: 3.5, currentHomeSpread: 3.5000001), .unchanged)
  }

  func testMovedSameUnderdogReportsDogPoints() {
    // Home favored by 7 -> 8.5: away dog now +8.5.
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: -7, currentHomeSpread: -8.5), .moved(8.5))
    // Home dog +3.5 -> +2.5.
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: 3.5, currentHomeSpread: 2.5), .moved(2.5))
  }

  func testFlippedFavoriteOrPickem() {
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: -1.5, currentHomeSpread: 1), .flipped)
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: 2, currentHomeSpread: 0), .flipped)
  }

  func testMissingValuesNeverBlock() {
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: -7, currentHomeSpread: nil), .unchanged)
    XCTAssertEqual(LineRecheck.evaluate(shownHomeSpread: nil, currentHomeSpread: -7), .unchanged)
  }

  func testWithLatestSpreadKeepsTheUnderdog() throws {
    let json = """
    {"id":"6f1c2c8e-0000-4000-8000-000000000001","season":2026,"week":9,"status":"scheduled","sport":"cfb",
     "home_name":"Home","away_name":"Away","home_team_id":"6f1c2c8e-0000-4000-8000-0000000000aa",
     "away_team_id":"6f1c2c8e-0000-4000-8000-0000000000bb","start_time":"2026-10-24T19:30:00Z","latest_spread":-7}
    """
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601withFallback
    let g = try dec.decode(Game.self, from: Data(json.utf8))
    let moved = g.withLatestSpread(-8.5)
    XCTAssertEqual(moved.underdogSpread, 8.5)
    XCTAssertEqual(moved.derivedUnderdogTeamId, g.derivedUnderdogTeamId)
    XCTAssertEqual(moved.id, g.id)
  }
}
