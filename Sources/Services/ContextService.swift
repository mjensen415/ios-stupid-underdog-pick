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
    // get_current_context_ios() RETURNS jsonb -- a single {"season":...,
    // "week":...} object, not an array of {"function_name": value} rows.
    // The old [[String: CurrentContext]] decode never matched what
    // PostgREST actually sends for a scalar-jsonb RPC, so this always
    // threw and silently fell through to fallbackFromAppState() below --
    // which reads a table nothing has written to since Oct 2025, so the
    // app was permanently stuck on last season regardless of what this
    // RPC (already fixed server-side to read site_settings) returned.
    let res = try await client.rpc("get_current_context_ios").execute()
    do {
      return try JSONDecoder().decode(CurrentContext.self, from: res.data)
    } catch {
      #if DEBUG
      print("[ContextService] RPC decode failed:", error, "raw:", String(data: res.data, encoding: .utf8) ?? "<non-utf8>")
      #endif
      throw ContextServiceError.noContextReturned
    }
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
