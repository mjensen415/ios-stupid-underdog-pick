import Foundation

// Mirrors src/lib/api/groups.ts. Field casing intentionally matches each
// edge function's actual JSON response exactly (there is no global
// keyDecodingStrategy in this codebase, see LeaderboardService) -- some
// responses are raw DB rows (snake_case) and some are hand-constructed by
// the edge function (camelCase), and that inconsistency is real, not a typo.

enum GroupRole: String, Codable, Equatable {
  case owner, admin, member, pending
}

// CFB and Pro Ball run as two separate competitions -- a group declares
// which one(s) it's for. "both" groups get a CFB/Pro Ball toggle on their
// leaderboard; single-sport groups just show that sport, no toggle.
enum GroupSport: String, Codable, Equatable, Hashable, CaseIterable {
  case cfb, nfl, both
}

struct MyGroup: Codable, Identifiable, Equatable {
  let group_id: UUID
  let name: String
  let slug: String
  let avatar_url: String?
  let is_private: Bool
  let description: String?
  let sport: GroupSport
  let member_count: Int
  let my_role: GroupRole
  let joined_at: String?
  let rank: Int?
  let my_points: Double?
  let leader_points: Double?

  var id: UUID { group_id }

  // Rank 1 always reads as "Leading" rather than "0 from leader" -- ties
  // for first also land on rank 1 (see get_my_group_standings), so this
  // covers "tied for the lead" too without a separate flag. nil when
  // standings haven't been computed for this group yet.
  var standingsLine: String? {
    guard let rank, let my_points, let leader_points else { return nil }
    if rank == 1 { return "YOU: 1/\(member_count) · Leading" }
    let gap = my_points - leader_points
    let gapText = gap == gap.rounded() ? String(format: "%.0f", gap) : String(format: "%.1f", gap)
    return "YOU: \(rank)/\(member_count) · \(gapText) from leader"
  }
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
  let sport: GroupSport
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
  let group_sport: GroupSport
  let slug: String
  let scope: String
  let season: Int
  let sport: String
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
  let sport: GroupSport
}

struct InviteEmailResult: Codable, Identifiable {
  let email: String
  let ok: Bool
  let error: String?

  var id: String { email }
}

struct CreateInviteResult: Codable {
  let inviteToken: String
  let joinUrl: String
  let emailResults: [InviteEmailResult]?
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
