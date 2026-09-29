import Foundation
import UIKit
import Supabase

// Server-driven "update available" nudge -- app_version_config.latest_version
// can be bumped in Supabase the moment a build goes live on the App Store,
// with no new build needed just to change the nudge itself.
struct AppVersionConfig: Decodable {
  let platform: String
  var latestVersion: String
  let updateMessage: String?
  /// Builds below this can't keep using the app (full-screen "Update
  /// required"). Null = no floor; only set it when an old build is truly
  /// broken against the backend.
  var minSupportedVersion: String? = nil

  enum CodingKeys: String, CodingKey {
    case platform
    case latestVersion = "latest_version"
    case updateMessage = "update_message"
    case minSupportedVersion = "min_supported_version"
  }
}

/// What the launch/foreground check decided.
enum AppUpdateState: Equatable {
  case current
  case available(AppVersionConfig)   // soft banner, dismissible per version
  case required(AppVersionConfig)    // blocking, below min_supported_version

  static func == (a: AppUpdateState, b: AppUpdateState) -> Bool {
    switch (a, b) {
    case (.current, .current): return true
    case let (.available(x), .available(y)), let (.required(x), .required(y)): return x.latestVersion == y.latestVersion
    default: return false
    }
  }
}

struct AppVersionService {
  let client: SupabaseClient

  func fetchConfig(platform: String = "ios") async throws -> AppVersionConfig? {
    let res = try await client
      .from("app_version_config")
      .select("platform, latest_version, update_message, min_supported_version")
      .eq("platform", value: platform)
      .execute()
    return try JSONDecoder().decode([AppVersionConfig].self, from: res.data).first
  }

  /// The version actually live on the App Store, straight from Apple's
  /// public lookup API -- so the nudge works the moment a release goes
  /// live, without anyone remembering to bump app_version_config. Skips a
  /// release this device's iOS can't install (minimumOsVersion).
  static func fetchStoreVersion() async -> String? {
    guard let bundleId = Bundle.main.bundleIdentifier,
          let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=us") else { return nil }
    var req = URLRequest(url: url)
    req.cachePolicy = .reloadIgnoringLocalCacheData
    req.timeoutInterval = 8
    struct Lookup: Decodable {
      struct Result: Decodable { let version: String; let minimumOsVersion: String? }
      let results: [Result]
    }
    guard let (data, _) = try? await URLSession.shared.data(for: req),
          let result = (try? JSONDecoder().decode(Lookup.self, from: data))?.results.first else { return nil }
    let deviceOS = await MainActor.run { UIDevice.current.systemVersion }
    if let minOS = result.minimumOsVersion, isVersion(minOS, newerThan: deviceOS) { return nil }
    return result.version
  }

  /// Newest of (App Store, app_version_config.latest_version) vs this
  /// build; the table still wins for the message and the hard floor.
  func checkForUpdate() async -> AppUpdateState {
    var installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    #if DEBUG
    // Simulator testing without touching prod config:
    // SIMCTL_CHILD_SUP_INSTALLED_VERSION=1.1.0 / SIMCTL_CHILD_SUP_MIN_VERSION=9.0
    let env = ProcessInfo.processInfo.environment
    if let fake = env["SUP_INSTALLED_VERSION"] { installed = fake }
    #endif
    async let configTask = try? fetchConfig()
    async let storeTask = Self.fetchStoreVersion()
    let (fetched, store) = await (configTask, storeTask)
    var config = (fetched ?? nil) ?? AppVersionConfig(platform: "ios", latestVersion: "0", updateMessage: nil)
    if let store, isVersion(store, newerThan: config.latestVersion) { config.latestVersion = store }
    #if DEBUG
    if let min = env["SUP_MIN_VERSION"] { config.minSupportedVersion = min }
    #endif

    if let floor = config.minSupportedVersion, isVersion(floor, newerThan: installed) {
      return .required(config)
    }
    if isVersion(config.latestVersion, newerThan: installed) { return .available(config) }
    return .current
  }
}

/// Numeric dotted-version comparison ("1.10.0" > "1.9.0"), not string
/// comparison -- a plain "1.10.0" < "1.9.0" lexicographic compare would be
/// wrong the moment either component reaches double digits.
func isVersion(_ latest: String, newerThan installed: String) -> Bool {
  let latestParts = latest.split(separator: ".").compactMap { Int($0) }
  let installedParts = installed.split(separator: ".").compactMap { Int($0) }
  let count = max(latestParts.count, installedParts.count)
  for i in 0..<count {
    let l = i < latestParts.count ? latestParts[i] : 0
    let inst = i < installedParts.count ? installedParts[i] : 0
    if l != inst { return l > inst }
  }
  return false
}
