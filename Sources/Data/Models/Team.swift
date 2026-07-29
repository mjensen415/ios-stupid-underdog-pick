import Foundation

struct Team: Codable, Identifiable, Equatable {
  let id: UUID
  let name: String
  let short_name: String
  let logo_url: String?
  let conference: String?
}

