import SwiftUI

struct MyPickRowView: View {
  let game: Game
  let logoFor: (UUID?) -> URL?
  var body: some View {
    GameRowView(game: game, logoFor: logoFor, isSelected: true)
  }
}
