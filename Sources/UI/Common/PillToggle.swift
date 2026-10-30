import SwiftUI

// Capsule pill selector -- extracted from SeasonLeaderboardView's inline
// season-pill styling (the only place this pattern lived before Groups
// needed it a second and third time: leaderboard scope, join-mode).
struct PillToggle<T: Hashable>: View {
  let options: [(label: String, value: T)]
  @Binding var selection: T
  var scrollable = false

  var body: some View {
    let content = HStack(spacing: 8) {
      ForEach(options, id: \.value) { option in
        let active = option.value == selection
        Button {
          selection = option.value
        } label: {
          Text(option.label)
            .font(BoldTheme.Fonts.body(13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Neutral ink, not gold or green: yellow is the screen's one
            // action, green means won/locked (de-slop colour roles).
            .background(active ? BoldTheme.Colors.text : BoldTheme.Colors.track)
            .foregroundColor(active ? BoldTheme.Colors.card : BoldTheme.Colors.textDim)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }

    if scrollable {
      ScrollView(.horizontal, showsIndicators: false) { content }
    } else {
      content
    }
  }
}
