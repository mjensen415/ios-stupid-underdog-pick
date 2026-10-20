import XCTest
@testable import Stupid_Underdog_Pick

/// Where-to-watch mapping (scripts/watch/watchLinks.test.ts), recent form
/// "from our side" (scripts/recent-form/recentForm.test.ts) and the
/// simplified Underdog Board row.
final class ProLogicTests: XCTestCase {
  // MARK: Watch links

  func testEspnNetworksDeepLinkToTheGameOthersToTheNetwork() {
    let l = WatchLinks.links(sport: .cfb, eventId: "401858274", networks: [
      BroadcastNetwork(name: "ESPN2", kind: "TV", market: "National"),
      BroadcastNetwork(name: "CBS", kind: "TV", market: "National"),
    ])
    XCTAssertEqual(l[0], WatchLink(label: "ESPN2", url: URL(string: "https://www.espn.com/college-football/game/_/gameId/401858274"), deep: true, local: false))
    XCTAssertEqual(l[1].url?.absoluteString, "https://www.paramountplus.com/live-tv/")
  }

  func testLocalOnlyChannelsShowAsNamesLinkedOnesWin() {
    XCTAssertEqual(WatchLinks.links(sport: .nhl, eventId: "1", networks: [BroadcastNetwork(name: "MSG", kind: "TV", market: "Home")]),
                   [WatchLink(label: "MSG", url: nil, deep: false, local: true)])
    let mixed = WatchLinks.links(sport: .nhl, eventId: "1", networks: [
      BroadcastNetwork(name: "MSG", kind: "TV", market: "Home"),
      BroadcastNetwork(name: "ESPN+", kind: "Streaming", market: "National"),
    ])
    XCTAssertEqual(mixed.map(\.label), ["ESPN+"])
    XCTAssertEqual(mixed[0].url?.absoluteString, "https://www.espn.com/nhl/game/_/gameId/1")
  }

  func testWatchPathsPerSportAndCap() {
    XCTAssertEqual(WatchLinks.espnGameURL(sport: .nfl, eventId: "9")?.absoluteString, "https://www.espn.com/nfl/game/_/gameId/9")
    XCTAssertEqual(WatchLinks.espnGameURL(sport: .nba, eventId: "9")?.absoluteString, "https://www.espn.com/nba/game/_/gameId/9")
    XCTAssertEqual(WatchLinks.link(sport: .nba, eventId: "9", network: BroadcastNetwork(name: "Peacock", kind: "Streaming", market: "National")).url?.absoluteString,
                   "https://www.peacocktv.com/sports")
    // Unknown national network: name only, not "local".
    XCTAssertEqual(WatchLinks.link(sport: .nba, eventId: "9", network: BroadcastNetwork(name: "Mystery TV", kind: "TV", market: "National")),
                   WatchLink(label: "Mystery TV", url: nil, deep: false, local: false))
    let many = ["ESPN", "ABC", "FOX", "CBS", "NBC"].map { BroadcastNetwork(name: $0, kind: "TV", market: "National") }
    XCTAssertEqual(WatchLinks.links(sport: .cfb, eventId: "1", networks: many).count, 3)
    XCTAssertEqual(WatchLinks.primary(sport: .cfb, eventId: "1", networks: [BroadcastNetwork(name: "MSG", kind: "TV", market: "Home")]), nil)
  }

  // MARK: Recent form

  // Real 2026 results. Spread is home-relative: positive = home is the dog.
  private let atTemple = RawFinal(home: "Temple", away: "UConn", homeKey: "t", awayKey: "u", homePts: 20, awayPts: 34, spread: -3.5)
  private let vsSyracuse = RawFinal(home: "UConn", away: "Syracuse", homeKey: "u", awayKey: "s", homePts: 41, awayPts: 42, spread: 6.5)

  func testFromTheTeamsSideWithItsOwnLine() {
    XCTAssertEqual(RecentForm.toFormGame(atTemple, key: "u", name: "UConn"),
                   FormGame(won: true, tie: false, ourPts: 34, theirPts: 20, opponent: "Temple", away: true, line: 3.5, dogWin: true, date: nil))
    let l = RecentForm.toFormGame(vsSyracuse, key: "u", name: "UConn")!
    XCTAssertEqual(l.won, false); XCTAssertEqual(l.line, 6.5); XCTAssertEqual(l.dogWin, false)
    XCTAssertEqual(l.opponent, "Syracuse"); XCTAssertEqual(l.away, false)
    // Temple's side of the same game: favored by 3.5, lost.
    XCTAssertEqual(RecentForm.toFormGame(atTemple, key: "t", name: nil)?.line, -3.5)
  }

  func testNameFallbackAndUnrelatedGamesSkipped() {
    let noIds = RawFinal(home: "Temple", away: "UConn", homeKey: nil, awayKey: nil, homePts: 20, awayPts: 34, spread: -3.5)
    XCTAssertEqual(RecentForm.toFormGame(noIds, key: nil, name: "UConn")?.won, true)
    XCTAssertNil(RecentForm.toFormGame(atTemple, key: "x", name: "Navy"))
    XCTAssertEqual(RecentForm.record([RecentForm.toFormGame(atTemple, key: "u", name: nil)!, RecentForm.toFormGame(vsSyracuse, key: "u", name: nil)!]), "1-1")
  }

  func testFormFormatting() {
    XCTAssertEqual(RecentForm.fmtLine(3.5), "+3.5")
    XCTAssertEqual(RecentForm.fmtLine(-7), "-7")
    XCTAssertEqual(RecentForm.fmtLine(nil), "")
    // 2026-10-18 01:30 UTC is still Oct 17 in Eastern time.
    XCTAssertEqual(RecentForm.fmtDate(ISO8601DateFormatter().date(from: "2026-10-18T01:30:00Z")), "10/17")
    let tie = RawFinal(home: "A", away: "B", homeKey: "a", awayKey: "b", homePts: 3, awayPts: 3, spread: nil)
    let t = RecentForm.toFormGame(tie, key: "a", name: nil)!
    XCTAssertTrue(t.tie); XCTAssertNil(t.line)
    XCTAssertEqual(RecentForm.record([t, RecentForm.toFormGame(atTemple, key: "u", name: nil)!]), "1-0-1")
    // Missing score: not a usable final.
    XCTAssertNil(RecentForm.toFormGame(RawFinal(home: "A", away: "B", homeKey: "a", awayKey: "b", homePts: nil, awayPts: 3, spread: nil), key: "a", name: nil))
  }

  // MARK: Underdog Board

  func testBoardDogFromTheDogsSideAndMarketFlip() {
    let id = UUID()
    let d = BoardDog.make(id: id, home: "Illinois", away: "Oregon", spread: 9, startTime: Date(),
                          marketDogTeam: "Illinois", marketDogWin: 0.22, marketFairSpread: 7.5)!
    XCTAssertEqual(d.dog, "Illinois"); XCTAssertTrue(d.homeDog); XCTAssertEqual(d.line, 9)
    XCTAssertEqual(d.market, 0.22); XCTAssertEqual(d.lineValue, 1.5)
    // Market thinks the other side is the dog: flip onto ours.
    let f = BoardDog.make(id: id, home: "South Carolina", away: "Tennessee", spread: -2.5, startTime: Date(),
                          marketDogTeam: "South Carolina", marketDogWin: 0.45, marketFairSpread: 1)!
    XCTAssertEqual(f.dog, "Tennessee")
    XCTAssertEqual(f.market!, 0.55, accuracy: 1e-9)
    XCTAssertEqual(f.lineValue, 3.5)
    XCTAssertNil(BoardDog.make(id: id, home: "A", away: "B", spread: 0, startTime: Date(), marketDogTeam: nil, marketDogWin: nil, marketFairSpread: nil))
    XCTAssertNil(BoardDog.make(id: id, home: "A", away: "B", spread: 3, startTime: Date(), marketDogTeam: nil, marketDogWin: nil, marketFairSpread: nil)?.market)
  }

  func testOptinStatusDecodes() throws {
    let s = try JSONDecoder().decode(ProOptinStatus.self, from: Data(#"{"eligible":true,"claimed":false,"until":"2027-02-15T00:00:00+00:00"}"#.utf8))
    XCTAssertTrue(s.eligible); XCTAssertFalse(s.claimed)
    XCTAssertNotNil(s.untilDate)
    let none = try JSONDecoder().decode(ProOptinStatus.self, from: Data(#"{"eligible":false,"claimed":false,"until":null}"#.utf8))
    XCTAssertEqual(none.untilText, "the end of the season")
  }
}
