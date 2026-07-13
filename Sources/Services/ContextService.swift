import Foundation
import Supabase

struct ContextService {
  let client: SupabaseClient

  func getCurrentContext() async throws -> CurrentContext {
    do {
      return try await fetchCurrentContextViaRPC()
    } catch ContextServiceError.noContextReturned {
      return try await fallbackFromAppState()
    } catch {
      // any network/JSON error → fallback too
      return try await fallbackFromAppState()
    }
  }
}

private enum ContextServiceError: Error {
  case noContextReturned
}

extension ContextService {
  private func fetchCurrentContextViaRPC() async throws -> CurrentContext {
    let res = try await client.rpc("get_current_context_ios").execute()
    let rows = try JSONDecoder().decode(
      [[String: CurrentContext]].self,
      from: res.data
    )
    guard let ctx = rows.first?["get_current_context_ios"]
    else { throw ContextServiceError.noContextReturned }
    return ctx
  }

  private func fallbackFromAppState() async throws -> CurrentContext {
    struct AppStateRow: Decodable { let season: Int; let week: Int }

    if let rows: [AppStateRow] = try? await client
      .from("app_state")
      .select("season, week")
      .eq("id", value: true)
      .limit(1)
      .execute()
      .value,
      let row = rows.first {
      return CurrentContext(season: row.season, week: row.week)
    }

    if let rows: [AppStateRow] = try? await client
      .from("app_state")
      .select("season, week")
      .eq("id", value: 1)
      .limit(1)
      .execute()
      .value,
      let row = rows.first {
      return CurrentContext(season: row.season, week: row.week)
    }

    let rows: [AppStateRow] = try await client
      .from("app_state")
      .select("season, week")
      .limit(1)
      .execute()
      .value
    if let row = rows.first { return CurrentContext(season: row.season, week: row.week) }
    throw ContextServiceError.noContextReturned
  }
}
