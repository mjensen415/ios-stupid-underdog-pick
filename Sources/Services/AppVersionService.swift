import Foundation
import Supabase

// Server-driven "update available" nudge -- app_version_config.latest_version
// can be bumped in Supabase the moment a build goes live on the App Store,
// with no new build needed just to change the nudge itself.
struct AppVersionConfig: Decodable {
  let platform: String
  let latestVersion: String
  let updateMessage: String?

  enum CodingKeys: String, CodingKey {
    case platform
    case latestVersion = "latest_version"
    case updateMessage = "update_message"
  }
}

struct AppVersionService {
  let client: SupabaseClient

  func fetchConfig(platform: String = "ios") async throws -> AppVersionConfig? {
    let res = try await client
      .from("app_version_config")
      .select("platform, latest_version, update_message")
      .eq("platform", value: platform)
      .execute()
    return try JSONDecoder().decode([AppVersionConfig].self, from: res.data).first
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
