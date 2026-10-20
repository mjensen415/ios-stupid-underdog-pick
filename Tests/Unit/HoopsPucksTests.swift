import XCTest
@testable import Stupid_Underdog_Pick

/// Same cases as the web's scripts/hoops-pucks/hoopsPucks.test.ts (the parts
/// that live in src/lib/hoopsPucks.ts; the ESPN parser tests are server-side).
final class HoopsPucksTests: XCTestCase {
  private func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)!
  }

  func testMoneylineToPoints() {
    XCTAssertEqual(HP.mlToPoints(150), 1.5)
    XCTAssertEqual(HP.mlToPoints(100), 1)
    XCTAssertEqual(HP.mlToPoints(330), 3.3)
    XCTAssertEqual(HP.mlToPoints(-150), 0)
    XCTAssertEqual(HP.mlToPoints(nil), 0)
  }

  func testUnderdogDetection() {
    XCTAssertEqual(HP.underdogSide(homeMl: -180, awayMl: 150), .away)
    XCTAssertEqual(HP.underdogSide(homeMl: 235, awayMl: -290), .home)
    XCTAssertEqual(HP.underdogSide(homeMl: 100, awayMl: -120), .home) // +100 vs -120: +100 is the dog
    XCTAssertNil(HP.underdogSide(homeMl: -110, awayMl: -110)) // pick'em
    XCTAssertNil(HP.underdogSide(homeMl: -115, awayMl: -105)) // both minus
    XCTAssertNil(HP.underdogSide(homeMl: 100, awayMl: 100))
    XCTAssertNil(HP.underdogSide(homeMl: nil, awayMl: 150))
  }

  func testEtWeekWindow() {
    // Tue Oct 20 2026 3pm EDT
    XCTAssertEqual(HP.weekStartET(iso("2026-10-20T19:00:00Z")), "2026-10-19")
    // Sun Oct 25 10pm EDT = Mon 02:00 UTC: still the Oct 19 week
    XCTAssertEqual(HP.weekStartET(iso("2026-10-26T02:00:00Z")), "2026-10-19")
    // Mon Oct 26 00:30 EDT: new week
    XCTAssertEqual(HP.weekStartET(iso("2026-10-26T04:30:00Z")), "2026-10-26")
    XCTAssertEqual(HP.etMidnightUtc("2026-10-19"), iso("2026-10-19T04:00:00.000Z"))
    // DST ends Nov 1 2026: week of Nov 2 starts at 05:00 UTC (EST)
    XCTAssertEqual(HP.etMidnightUtc("2026-11-02"), iso("2026-11-02T05:00:00.000Z"))
    let b = HP.weekBoundsUtc("2026-10-26") // spans the DST change
    XCTAssertEqual(b.start, iso("2026-10-26T04:00:00.000Z"))
    XCTAssertEqual(b.end, iso("2026-11-02T05:00:00.000Z"))
    XCTAssertEqual(HP.weekStartET(iso("2026-11-02T04:30:00Z")), "2026-10-26") // Sun 11:30pm EST
    XCTAssertEqual(HP.shiftWeek("2026-10-26", by: 1), "2026-11-02")
    XCTAssertEqual(HP.shiftWeek("2026-10-26", by: -1), "2026-10-19")
  }

  func testLocksAtStartTime() {
    let now = iso("2026-10-20T22:59:00Z")
    XCTAssertFalse(HP.isLocked(status: "scheduled", startTime: iso("2026-10-20T23:00:00Z"), now: now))
    XCTAssertTrue(HP.isLocked(status: "scheduled", startTime: iso("2026-10-20T22:59:00Z"), now: now))
    XCTAssertTrue(HP.isLocked(status: "in_progress", startTime: iso("2026-10-21T23:00:00Z"), now: now))
  }

  func testGrading() {
    let t = iso("2026-10-20T23:00:00Z")
    func grade(_ status: String, _ winner: HpSide?, _ start: Date = Date.distantPast) -> (HpPickResult, Double) {
      let r = HP.gradePick(side: .away, lockedMl: 170, lockedSpread: nil, weekStart: "2026-10-19",
                           sport: .nhl, status: status, winner: winner, startTime: start == .distantPast ? t : start)
      return (r.result, r.points)
    }
    XCTAssertEqual(grade("final", .away).0, .win)
    XCTAssertEqual(grade("final", .away).1, 1.7, accuracy: 1e-9)
    XCTAssertEqual(grade("final", .home).0, .loss)
    XCTAssertEqual(grade("final", .home).1, 0)
    XCTAssertEqual(grade("in_progress", nil).0, .pending)
    XCTAssertEqual(grade("postponed", nil).0, .void)
    // moved into next week -> void, slot refunded
    XCTAssertEqual(grade("scheduled", nil, iso("2026-10-27T23:00:00Z")).0, .void)
  }

  func testHoopsScoresTheSpreadPucksTheMoneyline() {
    XCTAssertEqual(HP.spreadDogSide(4.5), .home)
    XCTAssertEqual(HP.spreadDogSide(-3.5), .away)
    XCTAssertNil(HP.spreadDogSide(0))
    XCTAssertNil(HP.spreadDogSide(nil))
    // A spread dog can be a small moneyline favorite (-105 getting 1.5).
    XCTAssertEqual(HP.dogSide(sport: .nba, homeMl: -105, awayMl: -115, spread: 1.5), .home)
    XCTAssertEqual(HP.dogSide(sport: .nhl, homeMl: -225, awayMl: 185, spread: -1.5), .away)
    XCTAssertEqual(HP.pickPoints(sport: .nba, lockedMl: 150, lockedSpread: 3.5), 3.5)
    XCTAssertEqual(HP.pickPoints(sport: .nhl, lockedMl: 150, lockedSpread: nil), 1.5)
    let t = iso("2026-10-20T23:00:00Z")
    let win = HP.gradePick(side: .away, lockedMl: 150, lockedSpread: 4.5, weekStart: "2026-10-19", sport: .nba, status: "final", winner: .away, startTime: t)
    XCTAssertEqual(win.result, .win); XCTAssertEqual(win.points, 4.5)
    let loss = HP.gradePick(side: .away, lockedMl: 150, lockedSpread: 4.5, weekStart: "2026-10-19", sport: .nba, status: "final", winner: .home, startTime: t)
    XCTAssertEqual(loss.result, .loss); XCTAssertEqual(loss.points, 0)
  }

  func testLeaderboardTiebreakers() {
    let b = HP.rankBoard([
      .init(userId: "a", name: "A", points: 3, correct: 2, bestHit: 1.5),
      .init(userId: "b", name: "B", points: 3, correct: 1, bestHit: 3),
      .init(userId: "c", name: "C", points: 3, correct: 2, bestHit: 2),
      .init(userId: "d", name: "D", points: 3, correct: 2, bestHit: 2),
    ])
    XCTAssertEqual(b.map { "\($0.userId)\($0.rank)" }, ["c1", "d1", "a3", "b4"])
  }

  func testErrorCopy() {
    XCTAssertEqual(HP.errorMessage("weekly_limit"), "You've used all your picks this week.")
    XCTAssertEqual(HP.errorMessage("not_underdog"), "You can only pick the underdog.")
    XCTAssertEqual(HP.errorMessage("boom"), "boom")
    XCTAssertEqual(HP.errorMessage("ERROR: odds_stale (P0001)"), HP.errors["odds_stale"])
    XCTAssertEqual(HP.errorMessage(""), "Something went wrong.")
  }

  func testBadgesAndLogos() {
    XCTAssertEqual(HP.teamInitials(name: "San Jose", abbr: "SJ"), "SJ")
    XCTAssertEqual(HP.teamInitials(name: "Kestrel Bay", abbr: nil), "KB")
    XCTAssertEqual(HP.teamInitials(name: "New York (NYR)", abbr: nil), "NY")
    XCTAssertEqual(HP.logoURL(sport: .nba, abbr: "BOS")?.absoluteString, "https://stupidunderdogpick.com/team-logos/nba/bos.png")
    XCTAssertEqual(HP.logoURL(sport: .nhl, abbr: "UTA")?.absoluteString, "https://stupidunderdogpick.com/team-logos/nhl/utah.png")
    XCTAssertEqual(HP.logoURL(sport: .nba, abbr: "UTA")?.absoluteString, "https://stupidunderdogpick.com/team-logos/nba/uta.png")
    XCTAssertNil(HP.logoURL(sport: .nba, abbr: nil))
  }

  func testLineFormatting() {
    XCTAssertEqual(HP.fmtSpread(3.5), "+3.5")
    XCTAssertEqual(HP.fmtSpread(3), "+3")
    XCTAssertEqual(HP.fmtSpread(nil), "—")
    XCTAssertEqual(HP.fmtMl(150), "+150")
    XCTAssertEqual(HP.fmtMl(-205), "-205")
    XCTAssertEqual(HP.fmtMl(nil), "—")
    XCTAssertEqual(HP.fmtPts(1.5), "1.50")
    XCTAssertEqual(HP.fmtPts(3.3), "3.30")
    XCTAssertEqual(HP.sideLine(-4.5, side: .home), "-4.5")
    XCTAssertEqual(HP.sideLine(-4.5, side: .away), "+4.5")
    XCTAssertEqual(HP.sideLine(0, side: .away), "PK")
    XCTAssertEqual(HP.sideLine(nil, side: .away), "—")
    XCTAssertEqual(HP.sideLine(7, side: .home), "+7")
  }

  func testGroupedRecentFormNewestThreePerTeam() {
    let finals = (0..<5).map { i in
      RawFinal(home: "Home\(i)", away: "Away", homeKey: "h\(i)", awayKey: "A", homePts: 100, awayPts: 90 + i * 3, spread: 2)
    }
    let form = HoopsPucksService.groupForm(finals)
    XCTAssertEqual(form["A"]?.count, 3)
    XCTAssertEqual(form["A"]?.map(\.opponent), ["Home0", "Home1", "Home2"])
    XCTAssertEqual(form["h4"]?.first?.won, false) // 100-102
  }
}
