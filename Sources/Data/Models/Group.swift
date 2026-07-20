import Foundation

// Mirrors src/lib/api/groups.ts. Field casing intentionally matches each
// edge function's actual JSON response exactly (there is no global
// keyDecodingStrategy in this codebase, see LeaderboardService) -- some
// responses are raw DB rows (snake_case) and some are hand-constructed by
// the edge function (camelCase), and that inconsistency is real, not a typo.

enum GroupRole: String, Codable, Equatable {
  case owner, admin, member, pending
}

struct MyGroup: Codable, Identifiable, Equatable {
  let group_id: UUID
  let name: String
  let slug: String
  let avatar_url: String?
  let is_private: Bool
  let description: String?
  let member_count: Int
  let my_role: GroupRole
  let joined_at: String?
  let rank: Int?

  var id: UUID { group_id }
}

struct MyGroupsResult: Codable {
  let groups: [MyGroup]
}

struct DiscoverGroup: Decodable, Identifiable, Equatable {
  let id: UUID
  let name: String
  let slug: String
  let avatar_url: String?
  let is_private: Bool
  let member_count: Int
}

struct GroupLeaderboardEntry: Codable, Identifiable, Equatable {
  let rank: Int
  let user_id: UUID
  let display_name: String?
  let role: GroupRole
  let points: Double
  let wins: Int
  let losses: Int

  var id: UUID { user_id }
}

struct GroupLeaderboardResult: Codable {
  let group_id: UUID
  let group_name: String
  let slug: String
  let scope: String
  let season: Int
  let week: Int?
  let leaderboard: [GroupLeaderboardEntry]
}

struct GroupMember: Codable, Identifiable, Equatable {
  let user_id: UUID
  let display_name: String?
  let role: GroupRole
  let joined_at: String?

  var id: UUID { user_id }
}

struct GroupMembersResult: Codable {
  let group_id: UUID
  let group_name: String
  let slug: String
  let members: [GroupMember]
}

struct GroupInvite: Codable, Identifiable, Equatable {
  let invite_token: String
  let uses: Int
  let max_uses: Int?
  let expires_at: String?
  let revoked: Bool
  let created_at: String

  var id: String { invite_token }
}

struct GroupInvitesResult: Codable {
  let groupId: UUID
  let invites: [GroupInvite]
}

struct CreateGroupResult: Codable {
  let groupId: UUID
  let slug: String
}

struct CreateInviteResult: Codable {
  let inviteToken: String
  let joinUrl: String
}

struct JoinByTokenResult: Codable {
  let groupId: UUID
  let slug: String
  let name: String
  let status: String // "member" | "already_member"
}

struct UpdateGroupResult: Codable {
  let message: String
  let slug: String
}

struct JoinGroupResult: Codable {
  let status: String // "member" | "pending"
  let message: String
}

struct GroupMessageResult: Codable {
  let message: String
}
