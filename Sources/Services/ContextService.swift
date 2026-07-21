import Foundation
import Supabase

struct ContextService {
  let client: SupabaseClient

  func getCurrentContext(sport: String = "cfb") async throws -> CurrentContext {
    // get_current_context_ios(p_sport) RETURNS jsonb -- a single {"season":...,
    // "week":...} object, not an array of {"function_name": value} rows.
    // No fallback needed: the RPC itself falls back to date_part('year',
    // now())/week 1 server-side if site_settings has no key for the sport
    // yet (see the migration) -- a client-side fallback to `app_state`
    // (unused since Oct 2025) added nothing but a permanently-stale result.
    struct Params: Encodable { let p_sport: String }
    let res = try await client.rpc("get_current_context_ios", params: Params(p_sport: sport)).execute()
    return try JSONDecoder().decode(CurrentContext.self, from: res.data)
  }
}
