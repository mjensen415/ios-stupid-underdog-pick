import Foundation
import Supabase

struct CurrentContext: Codable { let season: Int; let week: Int }

enum ContextServiceError: LocalizedError {
  case noContextReturned
  var errorDescription: String? {
    switch self {
    case .noContextReturned: return "No context returned from server."
    }
  }
}

struct ContextService {
  let client: SupabaseClient
  func getCurrentContext() async throws -> CurrentContext {
    let res = try await client.rpc("get_current_context_ios").execute()
    #if DEBUG
    if let raw = String(data: res.data, encoding: .utf8) { print("[Context][RAW]", raw) }
    #endif
    let rows = try JSONDecoder().decode([[String: CurrentContext]].self, from: res.data)
    if let ctx = rows.first?["get_current_context_ios"] { return ctx }
    throw ContextServiceError.noContextReturned
  }
}


