import Foundation
import Supabase

// Every groups-* edge function wraps its body as {ok, data?, error?}
// (supabase/functions/_shared/group-helpers.ts's ApiResponse/successResponse/
// errorResponse) -- decode that envelope, not the payload directly.
private struct ApiEnvelope<T: Decodable>: Decodable {
  let ok: Bool
  let data: T?
  let error: String?
}

private struct ApiErrorBody: Decodable {
  let ok: Bool
  let error: String?
}

struct GroupsService {
  let client: SupabaseClient

  enum ServiceError: LocalizedError {
    case api(String)
    case missingData

    var errorDescription: String? {
      switch self {
      case .api(let message): return message
      case .missingData: return "Server returned an empty response."
      }
    }
  }

  private func invoke<T: Decodable>(_ name: String, method: FunctionInvokeOptions.Method = .post, query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> T {
    do {
      let envelope: ApiEnvelope<T>
      if let body {
        envelope = try await client.functions.invoke(name, options: .init(method: method, query: query, body: AnyEncodable(body)))
      } else {
        envelope = try await client.functions.invoke(name, options: .init(method: method, query: query))
      }
      guard let data = envelope.data else { throw ServiceError.missingData }
      return data
    } catch let FunctionsError.httpError(_, data) {
      if let body = try? JSONDecoder().decode(ApiErrorBody.self, from: data), let message = body.error {
        throw ServiceError.api(message)
      }
      throw ServiceError.api("Something went wrong. Please try again.")
    }
  }

  // MARK: - Group CRUD

  func createGroup(name: String, description: String?, isPrivate: Bool) async throws -> CreateGroupResult {
    struct Body: Encodable { let name: String; let description: String?; let isPrivate: Bool }
    return try await invoke("groups-create", body: Body(name: name, description: description, isPrivate: isPrivate))
  }

  func updateGroup(groupId: UUID, name: String?, description: String?, avatarUrl: String?, isPrivate: Bool?) async throws -> UpdateGroupResult {
    struct Body: Encodable { let groupId: UUID; let name: String?; let description: String?; let avatarUrl: String?; let isPrivate: Bool? }
    return try await invoke("groups-update", body: Body(groupId: groupId, name: name, description: description, avatarUrl: avatarUrl, isPrivate: isPrivate))
  }

  func deleteGroup(groupId: UUID) async throws -> GroupMessageResult {
    struct Body: Encodable { let groupId: UUID }
    return try await invoke("groups-delete", body: Body(groupId: groupId))
  }

  // MARK: - Membership

  func joinGroup(groupId: UUID) async throws -> JoinGroupResult {
    struct Body: Encodable { let groupId: UUID }
    return try await invoke("groups-join", body: Body(groupId: groupId))
  }

  func joinByToken(inviteToken: String) async throws -> JoinByTokenResult {
    struct Body: Encodable { let inviteToken: String }
    return try await invoke("groups-join-by-token", body: Body(inviteToken: inviteToken))
  }

  func approveMember(groupId: UUID, userId: UUID) async throws -> GroupMessageResult {
    struct Body: Encodable { let groupId: UUID; let userId: UUID }
    return try await invoke("groups-approve", body: Body(groupId: groupId, userId: userId))
  }

  func promoteToAdmin(groupId: UUID, userId: UUID) async throws -> GroupMessageResult {
    struct Body: Encodable { let groupId: UUID; let userId: UUID }
    return try await invoke("groups-promote-admin", body: Body(groupId: groupId, userId: userId))
  }

  func kickMember(groupId: UUID, userId: UUID) async throws -> GroupMessageResult {
    struct Body: Encodable { let groupId: UUID; let userId: UUID }
    return try await invoke("groups-kick", body: Body(groupId: groupId, userId: userId))
  }

  func leaveGroup(groupId: UUID) async throws -> GroupMessageResult {
    struct Body: Encodable { let groupId: UUID }
    return try await invoke("groups-leave", body: Body(groupId: groupId))
  }

  // MARK: - Reads

  func fetchMyGroups() async throws -> [MyGroup] {
    let result: MyGroupsResult = try await invoke("groups-mine", method: .get)
    return result.groups
  }

  func fetchGroupMembers(slug: String) async throws -> GroupMembersResult {
    try await invoke("groups-members", method: .get, query: [URLQueryItem(name: "slug", value: slug)])
  }

  /// Public-groups-only path goes through a SECURITY DEFINER RPC -- mirrors
  /// src/lib/api/groups.ts's fetchDiscoverGroups fix exactly. The anon/
  /// authenticated client has no table-level SELECT grant on groups/
  /// group_members, so a direct table query silently returned nothing for
  /// logged-out callers. See migration add_get_discover_groups_rpc.
  /// includePrivate stays supported (no current iOS caller uses it, but web's
  /// AllGroupsSidebar does) via the original direct-table path, which is
  /// fine for authenticated admins who do have table SELECT grants.
  func fetchDiscoverGroups(includePrivate: Bool = false, limit: Int = 20) async throws -> [DiscoverGroup] {
    if !includePrivate {
      struct Params: Encodable { let p_limit: Int }
      let res = try await client
        .rpc("get_discover_groups", params: Params(p_limit: limit))
        .execute()
      struct Row: Decodable { let id: UUID; let name: String; let slug: String; let avatar_url: String?; let member_count: Int }
      let rows = try JSONDecoder().decode([Row].self, from: res.data)
      return rows.map {
        DiscoverGroup(id: $0.id, name: $0.name, slug: $0.slug, avatar_url: $0.avatar_url, is_private: false, member_count: $0.member_count)
      }
    }

    let res = try await client
      .from("groups")
      .select("id, name, slug, avatar_url, is_private")
      .order("created_at", ascending: false)
      .limit(limit)
      .execute()

    struct Row: Decodable { let id: UUID; let name: String; let slug: String; let avatar_url: String?; let is_private: Bool }
    let rows = try JSONDecoder().decode([Row].self, from: res.data)
    guard !rows.isEmpty else { return [] }

    let groupIds = rows.map { $0.id }
    let memberRes = try await client
      .from("group_members")
      .select("group_id")
      .in("group_id", values: groupIds)
      .neq("role", value: "pending")
      .execute()
    struct MemberRow: Decodable { let group_id: UUID }
    let members = try JSONDecoder().decode([MemberRow].self, from: memberRes.data)
    let countMap = Dictionary(grouping: members, by: { $0.group_id }).mapValues { $0.count }

    return rows.map { row in
      DiscoverGroup(id: row.id, name: row.name, slug: row.slug, avatar_url: row.avatar_url, is_private: row.is_private, member_count: countMap[row.id] ?? 0)
    }
  }

  func fetchGroupLeaderboard(slug: String, scope: String, season: Int, week: Int?) async throws -> GroupLeaderboardResult {
    var query = [URLQueryItem(name: "slug", value: slug), URLQueryItem(name: "scope", value: scope), URLQueryItem(name: "season", value: "\(season)")]
    if let week { query.append(URLQueryItem(name: "week", value: "\(week)")) }
    return try await invoke("groups-leaderboard", method: .get, query: query)
  }

  // MARK: - Invites

  func createInvite(groupId: UUID, maxUses: Int?, expiresAt: String?) async throws -> CreateInviteResult {
    struct Body: Encodable { let groupId: UUID; let maxUses: Int?; let expiresAt: String? }
    return try await invoke("groups-create-invite", body: Body(groupId: groupId, maxUses: maxUses, expiresAt: expiresAt))
  }

  func revokeInvite(inviteToken: String) async throws -> GroupMessageResult {
    struct Body: Encodable { let inviteToken: String }
    return try await invoke("groups-revoke-invite", body: Body(inviteToken: inviteToken))
  }

  func fetchGroupInvites(groupId: UUID) async throws -> GroupInvitesResult {
    try await invoke("groups-invites", method: .get, query: [URLQueryItem(name: "groupId", value: groupId.uuidString)])
  }
}
