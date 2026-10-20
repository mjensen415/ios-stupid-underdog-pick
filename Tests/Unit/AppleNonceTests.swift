import XCTest
@testable import Stupid_Underdog_Pick

final class AppleNonceTests: XCTestCase {
  func testNonceIsRandomAndRightLength() {
    let a = AppleNonce.random(), b = AppleNonce.random()
    XCTAssertEqual(a.count, 32)
    XCTAssertNotEqual(a, b)
  }

  func testSha256MatchesKnownVector() {
    // SHA-256("abc"), FIPS 180-2 test vector. Apple gets this hex form.
    XCTAssertEqual(AppleNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }
}
