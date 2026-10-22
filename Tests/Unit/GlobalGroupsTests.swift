import XCTest
@testable import Stupid_Underdog_Pick

/// Same cases as the web's scripts/global-groups/globalGroups.test.ts.
final class GlobalGroupsTests: XCTestCase {
  private let globalId = UUID()
  private let mineId = UUID()

  private func league(_ id: UUID, name: String, sport: HpSport = .nba, global: Bool = false, role: String? = "member") -> HpLeague {
    HpLeague(id: id, name: name, sport: sport, picks_per_week: global ? 5 : 3, join_code: global ? "HOOPS0" : "ABC123",
             is_private: !global, is_global: global, role: role)
  }

  func testCopy() {
    XCTAssertEqual(GlobalGroups.tagline, "Global: everyone who plays. No group needed.")
    XCTAssertEqual(GlobalGroups.joinCTA, "Join the global group, it's free")
    XCTAssertEqual(GlobalGroups.picksPerWeek, 5)
  }

  func testGlobalListedFirstEvenBeforeJoining() {
    let mine = [league(mineId, name: "Friends")]
    let g = league(globalId, name: "Global Hoops", global: true, role: "member")
    let list = GlobalGroups.buildHpLeagueList(mine: mine, global: g, sport: .nba)
    XCTAssertEqual(list.map(\.id), [globalId, mineId])
    XCTAssertNil(list[0].role, "an unjoined Global league has no role")
  }

  func testGlobalNotDuplicatedOnceJoined() {
    let joined = league(globalId, name: "Global Hoops", global: true, role: "member")
    let list = GlobalGroups.buildHpLeagueList(mine: [league(mineId, name: "Friends"), joined], global: joined, sport: .nba)
    XCTAssertEqual(list.map(\.id), [globalId, mineId])
    XCTAssertEqual(list[0].role, "member")
  }

  func testOtherSportsGlobalIgnored() {
    let pucks = league(globalId, name: "Global Pucks", sport: .nhl, global: true)
    XCTAssertTrue(GlobalGroups.buildHpLeagueList(mine: [], global: pucks, sport: .nba).isEmpty)
  }

  func testDefaultLeague() {
    let g = league(globalId, name: "Global Hoops", global: true, role: nil)
    let mine = league(mineId, name: "Friends")
    // In a group: open on your group, not the unjoined Global.
    XCTAssertEqual(GlobalGroups.pickDefaultHpLeague([g, mine], requested: nil)?.id, mineId)
    // In no group: land on Global.
    XCTAssertEqual(GlobalGroups.pickDefaultHpLeague([g], requested: nil)?.id, globalId)
    // Asked for one: that one.
    XCTAssertEqual(GlobalGroups.pickDefaultHpLeague([g, mine], requested: globalId)?.id, globalId)
    // Asked for one that isn't listed: fall back.
    XCTAssertEqual(GlobalGroups.pickDefaultHpLeague([g, mine], requested: UUID())?.id, mineId)
    XCTAssertNil(GlobalGroups.pickDefaultHpLeague([], requested: nil))
  }

  func testNeedsGlobalJoin() {
    XCTAssertTrue(GlobalGroups.needsGlobalJoin(league(globalId, name: "G", global: true, role: nil)))
    XCTAssertFalse(GlobalGroups.needsGlobalJoin(league(globalId, name: "G", global: true, role: "member")))
    XCTAssertFalse(GlobalGroups.needsGlobalJoin(league(mineId, name: "Friends")))
    XCTAssertFalse(GlobalGroups.needsGlobalJoin(nil))
  }

  func testOnlySiteAdminsEditGlobal() {
    let gAdmin = league(globalId, name: "G", global: true, role: "admin")
    XCTAssertFalse(GlobalGroups.canEdit(gAdmin, isSiteAdmin: false))
    XCTAssertTrue(GlobalGroups.canEdit(gAdmin, isSiteAdmin: true))
    XCTAssertTrue(GlobalGroups.canEdit(league(mineId, name: "Friends", role: "admin"), isSiteAdmin: false))
    XCTAssertFalse(GlobalGroups.canEdit(league(mineId, name: "Friends", role: "member"), isSiteAdmin: false))
    XCTAssertFalse(GlobalGroups.canEdit(nil, isSiteAdmin: true))
  }

  func testDecodesIsGlobal() throws {
    let json = #"[{"id":"89086d30-37d6-48d7-8afe-9fe32d348b43","name":"Global Hoops","sport":"nba","picks_per_week":5,"join_code":"HOOPS0","is_private":false,"is_global":true},{"id":"be86235c-bf55-4252-bc40-a02b850042ad","name":"Old","sport":"nhl","picks_per_week":3,"join_code":"XYZ999","is_private":true}]"#
    let rows = try JSONDecoder().decode([HpLeague].self, from: Data(json.utf8))
    XCTAssertTrue(rows[0].is_global)
    XCTAssertFalse(rows[1].is_global, "missing column decodes as false")
    XCTAssertNil(rows[0].role)
  }

  func testGlobalAdminOnlyError() {
    XCTAssertEqual(HP.errorMessage("global_admin_only"), "Only SUP admins can change the global group.")
  }

  func testGlobalPickemsRows() throws {
    let json = #"[{"user_id":"6ba17134-785f-43db-b406-40cba47c93cd","display_name":null,"correct":7,"total_picks":10,"guessed_total_points":44,"actual_total_points":null}]"#
    let raw = try JSONDecoder().decode([GlobalPickemsRaw].self, from: Data(json.utf8))
    let week = GlobalPickemsRaw.rows(raw, scope: .week)[0]
    XCTAssertEqual(week.displayName, "Player")
    XCTAssertEqual(week.weekCorrect, 7)
    XCTAssertEqual(week.weekTotalPicks, 10)
    XCTAssertEqual(week.seasonCorrect, 0)
    XCTAssertEqual(week.guessedTotalPoints, 44)
    let season = GlobalPickemsRaw.rows(raw, scope: .season)[0]
    XCTAssertEqual(season.seasonCorrect, 7)
    XCTAssertEqual(season.weekCorrect, 0)
    XCTAssertNil(season.guessedTotalPoints)
  }
}
