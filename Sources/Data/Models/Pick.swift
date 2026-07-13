import Foundation

public struct Pick: Decodable, Identifiable {
  public let id: UUID
  public let user_id: UUID
  public let game_id: UUID
  public let picked_team_id: UUID
  public let season: Int
  public let week: Int
  public let created_at: String?
}
