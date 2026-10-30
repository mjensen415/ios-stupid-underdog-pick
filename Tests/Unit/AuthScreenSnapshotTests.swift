import XCTest
import SwiftUI
import Supabase
@testable import Stupid_Underdog_Pick

/// Renders the signed-out sign-in screens in a real UIWindow inside the test
/// host and saves PNGs, so the LAST USED tag and the forgot-password card
/// can be checked without signing a real account out (Supabase's default
/// sign-out is global and would revoke every session for that user).
///
/// Writes to $SUP_QA_DIR when set (pass TEST_RUNNER_SUP_QA_DIR=... to
/// xcodebuild); otherwise the test still renders but saves nothing.
@MainActor
final class AuthScreenSnapshotTests: XCTestCase {
  private let lastLoginKey = "sup.lastLoginMethod"
  private var savedLastLogin: Any?

  override func setUp() async throws {
    savedLastLogin = UserDefaults.standard.object(forKey: lastLoginKey)
  }

  override func tearDown() async throws {
    // Leave the simulator's real "last used" value exactly as it was.
    UserDefaults.standard.set(savedLastLogin, forKey: lastLoginKey)
  }

  func testSignInWithEmailLastUsed() async throws {
    UserDefaults.standard.set(LoginMethod.email.rawValue, forKey: lastLoginKey)
    try await snapshot(AuthView(), name: "06-signin-last-used-email")
  }

  func testSignInWithGoogleLastUsed() async throws {
    UserDefaults.standard.set(LoginMethod.google.rawValue, forKey: lastLoginKey)
    try await snapshot(AuthView(), name: "07-signin-last-used-google")
  }

  func testSignInWithAppleLastUsed() async throws {
    UserDefaults.standard.set(LoginMethod.apple.rawValue, forKey: lastLoginKey)
    try await snapshot(AuthView(), name: "08-signin-last-used-apple")
  }

  /// Native Sign in with Apple button, nothing tagged LAST USED.
  func testSignInNativeAppleButton() async throws {
    UserDefaults.standard.removeObject(forKey: lastLoginKey)
    try await snapshot(AuthView(), name: "10-signin-native-apple")
  }

  func testSignUpNativeAppleButton() async throws {
    UserDefaults.standard.removeObject(forKey: lastLoginKey)
    try await snapshot(AuthView(initialMode: .signup), name: "10b-signup-native-apple")
  }

  func testForgotPasswordCard() async throws {
    UserDefaults.standard.removeObject(forKey: lastLoginKey)
    try await snapshot(AuthView(initialMode: .forgot), name: "09-forgot-password")
  }

  func testMagicLink() async throws {
    try await snapshot(MagicLinkView(), name: "11-magic-link")
  }

  /// Onboarding step 1 ("What do you want to play?"). Its data loads point
  /// at a dead local address, so nothing touches the network and the step
  /// renders from local state only.
  func testOnboardingStepOne() async throws {
    let offline = SupabaseClient(supabaseURL: URL(string: "http://127.0.0.1:9")!, supabaseKey: "offline-test")
    try await snapshot(OnboardingFlowView(client: offline, isPresented: .constant(true)), name: "12-onboarding-step-1", client: offline)
  }

  private func snapshot<V: View>(_ view: V, name: String, client: SupabaseClient? = nil) async throws {
    let client = try client ?? SupabaseClientProvider.makeClient()
    let root = view
      .environmentObject(AppState())
      .environment(\.supabaseClient, client)
      .preferredColorScheme(.light)

    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.screen.bounds
    window.rootViewController = UIHostingController(rootView: root)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    // Let SwiftUI lay out and load fonts/images before capturing.
    try await Task.sleep(nanoseconds: 1_500_000_000)

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
