import Foundation

struct LeaderboardWeekRow: Codable, Identifiable, Equatable {
  let id: UUID
  let user_id: UUID
  let season: Int
  let week: Int
  let win: Int
  let loss: Int
  let points: Double
}

