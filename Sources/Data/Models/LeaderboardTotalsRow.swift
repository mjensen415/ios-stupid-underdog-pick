import Foundation

struct LeaderboardTotalsRow: Codable, Identifiable, Equatable {
  let id: UUID
  let user_id: UUID
  let wins: Int
  let losses: Int
  let pending: Int
  let total_points: Double
  let season: Int?
}

