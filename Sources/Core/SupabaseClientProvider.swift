import Foundation
import Supabase

enum ConfigError: LocalizedError {
  case missing(String)
  case invalidURL(String)

  var errorDescription: String? {
    switch self {
    case .missing(let key):
      return "Missing configuration: \(key)"
    case .invalidURL(let raw):
      return "Invalid SUPABASE_URL: \(raw)"
    }
  }
}

private enum ConfigSource: String {
  case env = "ENV"
  case plist = "PLIST"
  case override = "OVERRIDE"
}

final class SupabaseClientProvider {

  static func makeClient() throws -> SupabaseClient {
    let (urlString, urlSrc) = resolveValue(keys: ["SUPABASE_URL"],
                                           overrides: ["supabase_url_override"])
    let (anonKey, keySrc) = resolveValue(keys: ["SUPABASE_ANON_KEY"],
                                         overrides: ["supabase_anon_override"])

    guard let rawURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawURL.isEmpty else {
      throw ConfigError.missing("SUPABASE_URL (\(urlSrc?.rawValue ?? "NONE"))")
    }
    guard let url = URL(string: rawURL) else {
      throw ConfigError.invalidURL(rawURL)
    }

    guard let key = anonKey?.trimmingCharacters(in: .whitespacesAndNewlines),
          !key.isEmpty else {
      throw ConfigError.missing("SUPABASE_ANON_KEY (\(keySrc?.rawValue ?? "NONE"))")
    }

    #if DEBUG
    let redactedURL = rawURL.replacingOccurrences(of: "https://", with: "https://…")
    print("[Config] Source URL=\(urlSrc?.rawValue ?? "NONE") value=\(redactedURL)")
    print("[Config] Source KEY=\(keySrc?.rawValue ?? "NONE") present=\(!key.isEmpty)")
    #endif

    return SupabaseClient(supabaseURL: url, supabaseKey: key)
  }

  /// Try ENV → Info.plist → UserDefaults override
  private static func resolveValue(keys: [String], overrides: [String]) -> (String?, ConfigSource?) {
    // 1) ENV
    let env = ProcessInfo.processInfo.environment
    for k in keys {
      if let v = env[k], !v.isEmpty { return (v, .env) }
    }
    // 2) Info.plist
    for k in keys {
      if let v = Bundle.main.object(forInfoDictionaryKey: k) as? String, !v.isEmpty {
        return (v, .plist)
      }
    }
    // 3) UserDefaults overrides (dev)
    for k in overrides {
      if let v = UserDefaults.standard.string(forKey: k), !v.isEmpty {
        return (v, .override)
      }
    }
    return (nil, nil)
  }
}
