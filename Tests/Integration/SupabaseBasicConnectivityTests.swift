import XCTest
@testable import Stupid_Underdog_Pick

final class SupabaseBasicConnectivityTests: XCTestCase {
  func testEnvValuesExistAndClientInitializes() throws {
    let info = Bundle.main.infoDictionary ?? [:]
    let url = info["SUPABASE_URL"] as? String
    let key = info["SUPABASE_ANON_KEY"] as? String
    XCTAssertNotNil(url)
    XCTAssertNotNil(key)
    // Ensure provider initializes without crashing
    _ = try SupabaseClientProvider.makeClient()
  }
}


